import AppKit
import Carbon.HIToolbox
import JGDesign
import JGModel

// MARK: Data source and delegate

extension ListController: NSOutlineViewDataSource, NSOutlineViewDelegate {
    func outlineView(_: NSOutlineView, numberOfChildrenOfItem item: Any?) -> Int {
        outline.children(of: (item as? ListItem)?.folderID).count
    }

    func outlineView(_: NSOutlineView, child index: Int, ofItem item: Any?) -> Any {
        self.item(for: outline.children(of: (item as? ListItem)?.folderID)[index])
    }

    func outlineView(_: NSOutlineView, isItemExpandable item: Any) -> Bool {
        (item as? ListItem)?.folderID != nil
    }

    func outlineView(_ outlineView: NSOutlineView, viewFor tableColumn: NSTableColumn?, item: Any) -> NSView? {
        guard let item = item as? ListItem, let column = tableColumn.flatMap({ ListColumn(identifier: $0.identifier) }) else {
            return nil
        }
        return column == .name ? nameCell(for: item, in: outlineView) : textCell(column, for: item, in: outlineView)
    }

    func outlineView(_: NSOutlineView, rowViewForItem _: Any) -> NSTableRowView? {
        ListRowView()
    }

    func outlineViewSelectionDidChange(_: Notification) {
        selectionDidChange()
    }

    func outlineView(_: NSOutlineView, sortDescriptorsDidChange _: [NSSortDescriptor]) {
        sortDescriptorsChanged()
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        guard !isApplying, let id = (notification.userInfo?["NSObject"] as? ListItem)?.folderID else { return }
        model.listExpanded.insert(id)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        guard !isApplying, let id = (notification.userInfo?["NSObject"] as? ListItem)?.folderID else { return }
        model.listExpanded.remove(id)
    }

    /// Typing a name selects the row, as in Finder.
    func outlineView(_: NSOutlineView, typeSelectStringFor _: NSTableColumn?, item: Any) -> String? {
        guard let item = item as? ListItem else { return nil }
        switch item.row {
        case let .folder(id): return outline.folders[id]?.name
        case let .asset(id): return rows[id]?.name
        }
    }

    // MARK: Dragging files out (to sidebar folders, albums, Finder: as the grid, D-35)

    func outlineView(_: NSOutlineView, pasteboardWriterForItem item: Any) -> (any NSPasteboardWriting)? {
        guard let id = (item as? ListItem)?.assetID, let url = rows[id]?.url else { return nil }
        return url as NSURL
    }

    func outlineView(_: NSOutlineView, draggingSession _: NSDraggingSession, willBeginAt _: NSPoint, forItems _: [Any]) {
        InternalDrag.isActive = true
    }

    func outlineView(_: NSOutlineView, draggingSession _: NSDraggingSession, endedAt _: NSPoint, operation _: NSDragOperation) {
        InternalDrag.isActive = false
    }
}

extension ListColumn {
    init?(identifier: NSUserInterfaceItemIdentifier) {
        guard let column = Self.allCases.first(where: { $0.identifier == identifier }) else { return nil }
        self = column
    }
}

// MARK: Columns

extension ListController {
    /// Name, Date Modified, Size and Kind, each sorting the library by a click on its header.
    func addColumns() {
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
    }

    @objc func viewportChanged() {
        fitColumns()
    }

    /// The name takes whatever room the other columns leave (also after widths saved in a wider window), so Date,
    /// Size and Kind never fall off the right edge.
    func fitColumns() {
        let available = scrollView.contentView.bounds.width
        guard available > 0, let name = outlineView.tableColumn(withIdentifier: ListColumn.name.identifier) else { return }
        let others = outlineView.tableColumns.filter { $0 !== name }.reduce(CGFloat(0)) { $0 + $1.width }
        let spacing = outlineView.intercellSpacing.width * CGFloat(outlineView.numberOfColumns)
        let width = max(name.minWidth, available - others - spacing)
        if abs(name.width - width) > 0.5 {
            name.width = width
        }
    }
}

// MARK: Sort

extension ListController {
    /// The header's sort indicator follows the library's sort (Date Taken has no column: no indicator).
    func applySort() {
        let wanted = ListColumn(sort: model.state.sort).map { [NSSortDescriptor(key: $0.rawValue, ascending: model.state.ascending)] } ?? []
        guard outlineView.sortDescriptors != wanted else { return }
        isApplying = true
        outlineView.sortDescriptors = wanted
        isApplying = false
    }

    func sortDescriptorsChanged() {
        guard !isApplying, let descriptor = outlineView.sortDescriptors.first,
              let column = descriptor.key.flatMap(ListColumn.init(rawValue:))
        else { return }
        model.setSort(column.sort, ascending: descriptor.ascending)
    }
}

// MARK: Input

extension ListController {
    /// Double-click: a folder row shows that folder alone (as the sidebar does); a file opens in the viewer, a song
    /// with ⌥ in the window's mini player (D-88).
    @objc func doubleClicked() {
        guard let item = listItem(atRow: outlineView.clickedRow) else { return }
        open(item, option: NSEvent.modifierFlags.contains(.option))
    }

    /// Return: the focused file opens, or the selected folder shows.
    func openSelection() {
        if let focus = model.selection.focus {
            model.open(focus)
        } else if let item = listItem(atRow: outlineView.selectedRow) {
            open(item, option: false)
        }
    }

    private func open(_ item: ListItem, option: Bool) {
        switch item.row {
        case let .folder(id):
            model.select(folderID: id)
        case let .asset(id):
            if option, rows[id]?.kind == .audio {
                model.onPlayInMiniPlayer?(id)
            } else {
                model.open(id)
            }
        }
    }

    /// The keys the grid answers to: Space, Return, Esc and F for Quick Preview, F2 to rename, ⌫ in an album.
    /// Everything else (arrows, ← → to fold, typing a name) is the outline's own. Returns true when used.
    func handleKey(_ event: NSEvent) -> Bool {
        let plain = event.modifierFlags.isDisjoint(with: [.command, .control, .option, .shift])
        switch Int(event.keyCode) {
        case kVK_Space where plain:
            return model.onQuickPreviewKey?(.space) ?? false
        case kVK_Return, kVK_ANSI_KeypadEnter:
            if model.onQuickPreviewKey?(.returnKey) != true {
                openSelection()
            }
            return true
        case kVK_Escape:
            if model.onQuickPreviewKey?(.escape) != true {
                outlineView.deselectAll(nil)
            }
            return true
        case kVK_F2:
            model.performAction?(.rename)
            return true
        case kVK_ANSI_F where plain:
            return model.onQuickPreviewKey?(.fullScreen) ?? false
        case kVK_Delete where plain && model.state.albumID != nil:
            model.performAction?(.removeFromAlbum)
            return true
        default:
            return false
        }
    }

    /// Right-click: on an unselected file it becomes the selection first (as in Finder); a folder row gets Open and
    /// Show in Finder; empty space has no menu.
    func contextMenu(for event: NSEvent) -> NSMenu? {
        let row = outlineView.row(at: outlineView.convert(event.locationInWindow, from: nil))
        guard let item = listItem(atRow: row) else { return nil }
        if let id = item.folderID {
            return folderMenu(id)
        }
        guard let id = item.assetID else { return nil }
        if !model.selection.contains(id) {
            outlineView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        guard let target = model.actionTarget(sample: rows[id]?.url) else { return nil }
        return model.makeContextMenu?(target)
    }

    private func folderMenu(_ id: Int64) -> NSMenu {
        let menu = NSMenu()
        let open = NSMenuItem(
            title: String(localized: "Open", comment: "Action: open the file"),
            action: #selector(openFolder(_:)),
            keyEquivalent: ""
        )
        let reveal = NSMenuItem(
            title: String(localized: "Show in Finder", comment: "Sidebar folder menu"), action: #selector(showFolderInFinder(_:)),
            keyEquivalent: ""
        )
        for item in [open, reveal] {
            item.target = self
            item.representedObject = id
            menu.addItem(item)
        }
        return menu
    }

    @objc private func openFolder(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? Int64 else { return }
        model.select(folderID: id)
    }

    @objc private func showFolderInFinder(_ sender: NSMenuItem) {
        guard let id = sender.representedObject as? Int64, let folder = outline.folders[id] else { return }
        model.showInFinder(folder)
    }
}

// MARK: Rename in place

extension ListController: NSTextFieldDelegate {
    /// Edits a file's name in its row, Finder-style: the name without its extension is selected; Return keeps it,
    /// Esc gives up.
    func beginRename(_ id: Int64) {
        guard let row = row(ofAsset: id, unfold: true),
              let cell = outlineView.view(atColumn: 0, row: row, makeIfNecessary: true) as? ListNameCell,
              let name = rows[id]?.name
        else { return }
        outlineView.scrollRowToVisible(row)
        cell.label.isEditable = true
        cell.label.delegate = self
        outlineView.window?.makeFirstResponder(cell.label)
        let base = (name as NSString).deletingPathExtension
        cell.label.currentEditor()?.selectedRange = NSRange(location: 0, length: (base.isEmpty ? name : base).utf16.count)
    }

    func control(_ control: NSControl, textView _: NSTextView, doCommandBy selector: Selector) -> Bool {
        guard selector == #selector(NSResponder.cancelOperation(_:)), let field = control as? NSTextField else { return false }
        // Esc: the old name back, the list has the keyboard again.
        if let cell = field.superview as? ListNameCell, let id = cell.assetID, let name = rows[id]?.name {
            field.stringValue = name
        }
        outlineView.window?.makeFirstResponder(outlineView)
        return true
    }

    func controlTextDidEndEditing(_ notification: Notification) {
        guard let field = notification.object as? NSTextField, let cell = field.superview as? ListNameCell else { return }
        field.isEditable = false
        field.delegate = nil
        guard let id = cell.assetID, let asset = rows[id] else { return }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.isEmpty || name == asset.name {
            field.stringValue = asset.name
        } else {
            model.onInlineRename?(asset.url, name)
        }
        outlineView.window?.makeFirstResponder(outlineView)
    }
}

/// The list's outline view: the pane's clicks, the keys of `ListController.handleKey`, the context menu, Copy, and
/// stripes like Finder's (also below the last row).
final class ListOutlineView: NSOutlineView {
    weak var controller: ListController?

    override func mouseDown(with event: NSEvent) {
        controller?.model.onInteraction?()
        super.mouseDown(with: event)
    }

    /// The list takes the keyboard when it replaces the grid (View ▸ as List), as the grid had it.
    /// Another screen (1× or 2×): the visible rows draw their glyphs again for it.
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        let visible = rows(in: visibleRect)
        reloadData(forRowIndexes: IndexSet(integersIn: visible.lowerBound ..< visible.upperBound), columnIndexes: IndexSet(integer: 0))
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        // Not while a field is being edited (the search field keeps its typing).
        guard let window, !(window.firstResponder is NSText) else { return }
        window.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        if controller?.handleKey(event) == true {
            return
        }
        super.keyDown(with: event)
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        controller?.contextMenu(for: event)
    }

    @objc func copy(_: Any?) {
        controller?.model.performAction?(.copy)
    }

    override func drawBackground(inClipRect clipRect: NSRect) {
        let height = rowHeight + intercellSpacing.height
        guard height > 0 else { return }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            JGColor.bgPanel.nsColor.setFill()
        }
        let first = max(Int(floor(clipRect.minY / height)), 0)
        let last = Int(ceil(clipRect.maxY / height))
        guard first <= last else { return }
        for row in first ... last where !row.isMultiple(of: 2) {
            NSRect(x: clipRect.minX, y: CGFloat(row) * height, width: clipRect.width, height: height).fill()
        }
    }
}

extension ListOutlineView: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(copy(_:)) {
            return controller?.model.selection.isEmpty == false
        }
        return true
    }
}
