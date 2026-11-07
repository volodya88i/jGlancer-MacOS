import AppKit
import JGDesign
import JGModel
import JGThumbs
import UniformTypeIdentifiers

/// Drives the library's list view (D-125): a Finder-style outline of the folder shown, rows loaded lazily for what is
/// on screen, small thumbnails, the library's selection and sort kept in step both ways.
@MainActor
final class ListController: NSObject {
    let scrollView = NSScrollView()
    let outlineView = ListOutlineView()
    let model: LibraryModel

    private(set) var outline = ListOutline()
    /// One object per row, kept across reloads (`ListItem` equality also keeps them).
    private var items: [ListOutline.Row: ListItem] = [:]
    /// Full rows of the assets shown (bounded), rows being fetched, rows that changed in the store.
    var rows: [Int64: Asset] = [:]
    private var rowsInFlight: Set<Int64> = []
    private var staleRows: Set<Int64> = []
    private var wantedRows: Set<Int64> = []
    private var fetchScheduled = false
    /// Folder rows' modification dates, read from disk off the main thread.
    var folderDates: [Int64: Date] = [:]
    /// Files kept only in the cloud whose stored thumbnail was looked up (D-124).
    var cloudLookups: Set<Int64> = []

    private var lastRefsVersion = -1
    private var lastRowsVersion = 0
    private var lastShown: FolderNode?
    private var lastFocusRequest = 0
    private var lastRenameSerial = 0
    var lastSelection: SelectionModel?
    /// True while the controller itself changes the outline's selection or sort (no echo back to the model).
    var isApplying = false
    private var needsFocusRestore = true
    private static let rowCapacity = 10000

    init(model: LibraryModel) {
        self.model = model
        super.init()
        outlineView.controller = self
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.headerView = NSTableHeaderView()
        outlineView.style = .plain
        outlineView.backgroundColor = .clear
        outlineView.allowsMultipleSelection = true
        outlineView.allowsEmptySelection = true
        outlineView.allowsColumnReordering = true
        outlineView.columnAutoresizingStyle = .firstColumnOnlyAutoresizingStyle
        outlineView.intercellSpacing = NSSize(width: JGSpacing.s, height: 0)
        outlineView.indentationPerLevel = JGSpacing.m
        outlineView.autoresizesOutlineColumn = false
        outlineView.target = self
        outlineView.doubleAction = #selector(doubleClicked)
        outlineView.setDraggingSourceOperationMask(.copy, forLocal: false)
        outlineView.setDraggingSourceOperationMask([.move, .copy], forLocal: true)
        outlineView.setAccessibilityLabel(String(localized: "Library", comment: "Accessibility label of the thumbnail grid"))
        for column in ListColumn.allCases {
            let tableColumn = NSTableColumn(identifier: column.identifier)
            tableColumn.title = column.title
            tableColumn.sortDescriptorPrototype = NSSortDescriptor(key: column.rawValue, ascending: true)
            switch column {
            case .name:
                tableColumn.minWidth = JGMetrics.sidebarWidth
                tableColumn.resizingMask = [.autoresizingMask, .userResizingMask]
            case .date: tableColumn.width = JGMetrics.listDateColumnWidth
            case .size: tableColumn.width = JGMetrics.listSizeColumnWidth
            case .kind: tableColumn.width = JGMetrics.listKindColumnWidth
            }
            if column == .size {
                tableColumn.headerCell.alignment = .right
            }
            outlineView.addTableColumn(tableColumn)
            if column == .name {
                outlineView.outlineTableColumn = tableColumn
            }
        }
        // The user's column widths and order, per pane.
        outlineView.autosaveName = model.isFollower ? "LibraryList.secondPane" : "LibraryList"
        outlineView.autosaveTableColumns = true
        scrollView.documentView = outlineView
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.automaticallyAdjustsContentInsets = false
    }

    /// The bars over the list (D-114): the header and rows start below the top bar and end above the status bubble.
    func setInsets(_ insets: NSEdgeInsets) {
        let current = scrollView.contentInsets
        guard current.top != insets.top || current.bottom != insets.bottom else { return }
        scrollView.contentInsets = insets
    }

    // MARK: Model sync

    /// Applies model changes; cheap when nothing relevant changed.
    func sync(shown: FolderNode?) {
        outlineView.rowHeight = CGFloat(model.state.listRowHeight)
        applySort()
        if model.rowsVersion != lastRowsVersion {
            // Flagged, moved or renamed files keep their ids: rows are fetched again while the old ones stay drawn.
            lastRowsVersion = model.rowsVersion
            staleRows = Set(rows.keys)
            cloudLookups.removeAll()
            folderDates.removeAll()
            loadFolderDates()
            fetchVisibleRows()
        }
        if model.refsVersion != lastRefsVersion || shown != lastShown {
            lastRefsVersion = model.refsVersion
            lastShown = shown
            rebuild(shown: shown)
        }
        applySelection()
        if model.focusRequest != lastFocusRequest {
            lastFocusRequest = model.focusRequest
            outlineView.window?.makeFirstResponder(outlineView)
            revealFocus()
        }
        if let request = model.inlineRenameRequest, request.serial != lastRenameSerial {
            lastRenameSerial = request.serial
            beginRename(request.id)
        }
    }

    private func rebuild(shown: FolderNode?) {
        outline = ListOutline(
            refs: model.refs, shown: shown, foldersDescending: model.state.sort == .name && !model.state.ascending
        )
        isApplying = true
        outlineView.reloadData()
        // Folders unfolded before stay unfolded (outer ones first, so inner ones exist).
        expandRemembered(in: nil)
        isApplying = false
        lastSelection = nil
        applySelection()
        loadFolderDates()
        if needsFocusRestore, model.isLoaded {
            needsFocusRestore = false
            revealFocus()
        }
    }

    private func expandRemembered(in folder: Int64?) {
        for case let .folder(id) in outline.children(of: folder) where model.listExpanded.contains(id) {
            outlineView.expandItem(item(for: .folder(id)))
            expandRemembered(in: id)
        }
    }

    func item(for row: ListOutline.Row) -> ListItem {
        if let item = items[row] {
            return item
        }
        let item = ListItem(row)
        items[row] = item
        return item
    }

    func listItem(atRow row: Int) -> ListItem? {
        row >= 0 ? outlineView.item(atRow: row) as? ListItem : nil
    }

    /// The outline row of an asset, unfolding its folders first when `unfold`; nil when it is not in the list.
    func row(ofAsset id: Int64, unfold: Bool) -> Int? {
        if unfold {
            for folder in outline.folderPath(toAsset: id) {
                outlineView.expandItem(item(for: .folder(folder)))
            }
        }
        let row = outlineView.row(forItem: item(for: .asset(id)))
        return row >= 0 ? row : nil
    }

    // MARK: Selection

    /// The library's selection shown in the outline (after a reload, a restore, a reveal or a change elsewhere).
    func applySelection() {
        guard model.selection != lastSelection else { return }
        lastSelection = model.selection
        var indexes = IndexSet()
        for id in model.selection.selected {
            if let row = row(ofAsset: id, unfold: false) {
                indexes.insert(row)
            }
        }
        isApplying = true
        outlineView.selectRowIndexes(indexes, byExtendingSelection: false)
        isApplying = false
    }

    /// The outline's selection into the library: files only (a selected folder row is the list's own).
    func selectionDidChange() {
        guard !isApplying else { return }
        let ids = outlineView.selectedRowIndexes.compactMap { listItem(atRow: $0)?.assetID }
        let focus = listItem(atRow: outlineView.selectedRow)?.assetID ?? ids.last
        var selection = SelectionModel()
        selection.restore(ids, focus: focus)
        lastSelection = selection
        model.selection = selection
    }

    private func revealFocus() {
        guard let focus = model.selection.focus, let row = row(ofAsset: focus, unfold: true) else { return }
        lastSelection = nil
        applySelection()
        outlineView.scrollRowToVisible(row)
    }

    // MARK: Rows

    /// The asset's row, asking for it (in one batch with the others on screen) when it is missing or stale.
    func asset(_ id: Int64) -> Asset? {
        if rows[id] == nil || staleRows.contains(id) {
            want(id)
        }
        return rows[id]
    }

    private func want(_ id: Int64) {
        guard !rowsInFlight.contains(id) else { return }
        wantedRows.insert(id)
        guard !fetchScheduled else { return }
        fetchScheduled = true
        Task { [weak self] in
            // Every cell the outline asks for in this pass joins the batch.
            await Task.yield()
            self?.fetchWanted()
        }
    }

    private func fetchWanted() {
        fetchScheduled = false
        let ids = Array(wantedRows)
        wantedRows.removeAll()
        guard !ids.isEmpty else { return }
        rowsInFlight.formUnion(ids)
        let store = model.store
        Task { [weak self] in
            let assets = await (try? store.assets(ids: ids)) ?? []
            guard let self else { return }
            rowsInFlight.subtract(ids)
            staleRows.subtract(ids)
            if rows.count + assets.count > Self.rowCapacity {
                rows.removeAll()
            }
            for asset in assets {
                rows[asset.id] = asset
            }
            reloadCells(of: Set(assets.map(\.id)))
        }
    }

    private func fetchVisibleRows() {
        let visible = outlineView.rows(in: outlineView.visibleRect)
        for row in visible.lowerBound ..< visible.upperBound {
            if let id = listItem(atRow: row)?.assetID {
                want(id)
            }
        }
    }

    /// Redraws the visible rows of `ids`.
    func reloadCells(of ids: Set<Int64>) {
        let visible = outlineView.rows(in: outlineView.visibleRect)
        var indexes = IndexSet()
        for row in visible.lowerBound ..< visible.upperBound {
            if let id = listItem(atRow: row)?.assetID, ids.contains(id) {
                indexes.insert(row)
            }
        }
        guard !indexes.isEmpty else { return }
        outlineView.reloadData(forRowIndexes: indexes, columnIndexes: IndexSet(integersIn: 0 ..< outlineView.numberOfColumns))
    }

    /// Folder rows show their folder's modification date, read off the main thread.
    private func loadFolderDates() {
        let urls = outline.folders.compactMap { id, folder in model.url(of: folder).map { (id, $0) } }
        guard !urls.isEmpty else { return }
        Task { [weak self] in
            let dates = await Task.detached(priority: .utility) {
                urls.reduce(into: [Int64: Date]()) { result, entry in
                    result[entry.0] = (try? entry.1.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                }
            }.value
            guard let self else { return }
            folderDates.merge(dates) { _, new in new }
            outlineView.reloadData(
                forRowIndexes: IndexSet(dates.keys.map { self.outlineView.row(forItem: self.item(for: .folder($0))) }.filter { $0 >= 0 }),
                columnIndexes: IndexSet(integersIn: 0 ..< outlineView.numberOfColumns)
            )
        }
    }
}
