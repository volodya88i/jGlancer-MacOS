import AppKit
import JGDesign
import JGModel
import JGStore
import JGThumbs

/// Drives the library grid: data source, visible-range prefetch of rows and thumbnails with
/// cancellation (docs/ARCHITECTURE.md §6–7), and selection input (click, ⇧/⌘, marquee, keyboard).
@MainActor
final class GridController: NSObject, NSCollectionViewDataSource {
    let scrollView = NSScrollView()
    let collectionView = GridCollectionView()
    let layout = GridLayout()
    let model: LibraryModel

    /// Full rows of recently shown assets (bounded).
    var rows: [Int64: Asset] = [:]
    var rowQueue: [Int64] = []
    static let rowCapacity = 5000
    var rowsInFlight: Set<Int64> = []
    /// Rows that changed in the store (a flag, a move, a rename): still drawn, fetched again as they show (D-113).
    var staleRows: Set<Int64> = []

    var thumbnailTasks: [Int64: (task: Task<Void, Never>, priority: ThumbnailPriority)] = [:]
    /// Scroll speed and the screen it predicts (`GridController+Prefetch`, D-81).
    var prefetch = ScrollPrefetch()
    var settleTask: Task<Void, Never>?
    /// The end of a live tile-size change (`GridController+Sizing`, D-93).
    var sizingSettle: Task<Void, Never>?
    /// When the tile size last changed: a step soon after another joins the live change, however big (D-112).
    var lastSizeChange: CFTimeInterval = 0
    /// Keys of additive glides, so they stack.
    var reflowSerial = 0
    /// Tiles that flew past while scrolling, lowered to background, oldest first.
    var trail: [Int64] = []
    /// Priority changes not yet sent to the thumbnail service, and the task sending them.
    var pendingPriorities: [Int64: (ThumbnailRequest, ThumbnailPriority)] = [:]
    var priorityFlush: Task<Void, Never>?
    private var lastRefsVersion = -1
    private var lastRowsVersion = 0
    private var lastRenameSerial = 0
    /// The name being edited in place.
    var renaming: GridRenameState?

    var lastSelection = SelectionModel()
    let marqueeLayer = CALayer()
    /// Where dragged tiles would land when reordering an album.
    let dropIndicator = CALayer()
    init(model: LibraryModel) {
        self.model = model
        super.init()
        collectionView.collectionViewLayout = layout
        collectionView.dataSource = self
        collectionView.controller = self
        collectionView.isSelectable = false
        collectionView.backgroundColors = [.clear]
        collectionView.register(ThumbnailItem.self, forItemWithIdentifier: ThumbnailItem.identifier)
        collectionView.setAccessibilityLabel(String(localized: "Library", comment: "Accessibility label of the thumbnail grid"))
        scrollView.documentView = collectionView
        scrollView.automaticallyAdjustsContentInsets = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification, object: scrollView.contentView
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(viewportChanged), name: NSView.frameDidChangeNotification, object: scrollView.contentView
        )
        marqueeLayer.borderWidth = JGMetrics.outlineWidth
        marqueeLayer.isHidden = true
        marqueeLayer.zPosition = 10
        dropIndicator.zPosition = 10
        dropIndicator.isHidden = true
    }

    /// The bars over the grid (D-114): content and scroller start below the top bar and end above the status bar.
    func setInsets(_ insets: NSEdgeInsets) {
        let current = scrollView.contentInsets
        guard current.top != insets.top || current.bottom != insets.bottom else { return }
        scrollView.contentInsets = insets
        scrollView.scrollerInsets = NSEdgeInsets(top: 0, left: 0, bottom: 0, right: 0)
        layout.invalidateLayout()
    }

    // MARK: Model sync

    /// Applies model changes; cheap when nothing relevant changed.
    func sync() {
        let liveSizing = beginSizing()
        // While the size changes live, thumbnails keep their size: the new one is asked for once it settles.
        let bucket = layout.liveScale == nil ? sizeBucket : currentBucket
        let bucketChanged = bucket != currentBucket
        let plan = planReflow(
            sortChanged: model.refsVersion != lastRefsVersion
                && lastSort.map { $0.0 != model.state.sort || $0.1 != model.state.ascending } == true,
            toggled: model.refsVersion != lastRefsVersion ? model.lastSequenceToggle : nil,
            liveSizing: liveSizing
        )
        lastSort = (model.state.sort, model.state.ascending)
        currentBucket = bucket
        layout.targetTileSide = model.state.tileSide
        layout.showsCaptions = model.state.showNames
        if model.rowsVersion != lastRowsVersion {
            // Flagged, moved or renamed files keep their ids: the tiles keep what they show while the rows are fetched
            // again, so nothing blanks out and thumbnails stay (D-113).
            lastRowsVersion = model.rowsVersion
            staleRows = Set(rows.keys)
        }
        if let request = model.inlineRenameRequest, request.serial != lastRenameSerial {
            lastRenameSerial = request.serial
            beginRename(request.id)
        }
        if model.refsVersion != lastRefsVersion {
            endRename(commit: false)
            lastRefsVersion = model.refsVersion
            cancelAllThumbnails()
            collectionView.reloadData()
            restoreFocusIfNeeded()
        } else if bucketChanged {
            cancelAllThumbnails()
            reconfigureVisibleItems()
        } else {
            reconfigureVisibleItems()
        }
        syncSelectionAndFocus()
        updateMarqueeColors()
        finish(plan)
        updateWindow()
    }

    private func syncSelectionAndFocus() {
        if model.selection != lastSelection {
            lastSelection = model.selection
            refreshSelection()
        }
        if model.focusRequest != lastFocusRequest {
            lastFocusRequest = model.focusRequest
            collectionView.window?.makeFirstResponder(collectionView)
            if let focus = model.selection.focus, let index = model.order.index(of: focus) {
                scrollToVisible(index)
            }
        }
    }

    var currentBucket: ThumbnailBucket = .medium
    /// The sort of the last sync: a new one may glide the tiles.
    private var lastSort: (AssetQuery.Sort, Bool)?
    private var lastFocusRequest = 0
    private var needsFocusRestore = true

    /// The thumbnail size for the tile size set.
    var sizeBucket: ThumbnailBucket {
        ThumbnailBucket.covering(longestSidePixels: Int(model.state.tileSide * backingScale))
    }

    private var backingScale: CGFloat {
        collectionView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
    }

    private func restoreFocusIfNeeded() {
        guard needsFocusRestore, model.isLoaded else { return }
        needsFocusRestore = false
        if let focus = model.selection.focus, let index = model.order.index(of: focus) {
            scrollToVisible(index)
        }
    }

    // MARK: Data source

    func collectionView(_: NSCollectionView, numberOfItemsInSection _: Int) -> Int {
        model.refs.count
    }

    func collectionView(_ collectionView: NSCollectionView, itemForRepresentedObjectAt indexPath: IndexPath) -> NSCollectionViewItem {
        let item = collectionView.makeItem(withIdentifier: ThumbnailItem.identifier, for: indexPath)
        if let item = item as? ThumbnailItem {
            configure(item, at: indexPath.item)
        }
        return item
    }

    private func configure(_ item: ThumbnailItem, at index: Int) {
        guard index < model.refs.count, let tile = item.tile else { return }
        let ref = model.refs[index]
        item.assetID = ref.id
        let asset = rows[ref.id]
        tile.content = ThumbnailTileView.Content(
            name: asset?.name,
            kind: ref.kind,
            duration: asset?.duration.flatMap(DurationFormat.positional),
            showsCaption: layout.captionsVisible,
            accessibilityKind: Self.kindName(ref.kind),
            flag: asset?.flag ?? .none,
            sequenceFrames: model.sequence(headedBy: ref.id)?.frames.count,
            sequenceUnfolded: !model.isFolded(ref.id)
        )
        tile.isSelected = model.selection.contains(ref.id)
        tile.showsCrosshairs = model.decorCrosshairs
        if let asset, let cached = model.thumbnails.cachedThumbnail(for: request(for: asset)) {
            tile.image = cached
            tile.isLoading = false
            if cached != nil {
                LaunchMetrics.markFirstTile()
            }
        } else if let asset, let standIn = standInThumbnail(for: asset) {
            // Another size stands in until this one arrives (a new tile size, D-83).
            tile.image = standIn
            tile.isLoading = false
        } else {
            tile.image = nil
            tile.isLoading = true
        }
    }

    func reconfigureVisibleItems() {
        for case let item as ThumbnailItem in collectionView.visibleItems() {
            guard let indexPath = collectionView.indexPath(for: item) else { continue }
            configure(item, at: indexPath.item)
        }
    }

    func refreshSelection() {
        for case let item as ThumbnailItem in collectionView.visibleItems() where item.assetID != nil {
            item.tile?.isSelected = item.assetID.map(model.selection.contains) ?? false
        }
    }

    private func updateMarqueeColors() {
        collectionView.effectiveAppearance.performAsCurrentDrawingAppearance {
            marqueeLayer.borderColor = JGColor.accent.nsColor.cgColor
            marqueeLayer.backgroundColor = JGColor.accentDim.nsColor.withAlphaComponent(JGMetrics.marqueeFillOpacity).cgColor
        }
    }
}
