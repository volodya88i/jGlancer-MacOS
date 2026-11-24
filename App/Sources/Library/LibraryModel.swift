import AppKit
import JGActions
import JGModel
import JGScanner
import JGStore
import JGThumbs
import Observation

/// State and intents of the library window: roots and folders, the current query, the asset index,
/// the selection, background indexing (docs/FEATURES.md §1). Views read it; the grid drives it.
@MainActor
@Observable
final class LibraryModel {
    let store: LibraryStore
    let scanner: LibraryScanner
    let thumbnails: ThumbnailService

    /// Roots, folder trees and albums belong to the main pane; a split view's second pane mirrors them (D-89).
    private(set) var roots: [RootFolder] = [] {
        didSet { follower?.mirror(self) }
    }

    /// The library folders' own icons (D-129), pictures decoded; the main pane's (the sidebar shows them).
    var rootIcons: [Int64: FolderIconImage] = [:]

    /// Virtual albums in sidebar order, and the albums of each asset.
    var albums: [Album] = [] {
        didSet { follower?.mirror(self) }
    }

    var albumMemberships: [Int64: Set<Int64>] = [:] {
        didSet { follower?.mirror(self) }
    }

    /// The split view's second pane, which mirrors this one's roots, trees and albums (D-89).
    @ObservationIgnored weak var follower: LibraryModel?
    /// True for the second pane.
    let isFollower: Bool
    /// Settings: dragging reorders albums (Advanced); "+" marks on selected tiles (decor).
    var decorCrosshairs = false
    /// Tiles glide to new places (Settings → Appearance → Effects, not with Reduce Motion; D-83).
    var animatesGrid = false
    /// Reduce Motion (the app's or the system's): no fold and unfold flights either.
    var reducesMotion = false
    var trees: [Int64: FolderNode] = [:] {
        didSet {
            if !isFollower {
                follower?.mirror(self)
            }
        }
    }

    /// Watching and metadata extraction in the background.
    let indexer: LibraryIndexer

    /// Roots whose folder is unavailable (unmounted volume, moved or deleted).
    var offlineRoots: Set<Int64> {
        indexer.offlineRoots
    }

    /// Folders expanded in the sidebar.
    var expandedFolders: Set<Int64> = []

    /// Restorable view state: scope, filters, sort, tile size, names, saved selection.
    private(set) var state: LibraryViewState

    /// The sorted index of the current query as shown (folded image sequences show their head only), and its
    /// id → position map.
    private(set) var refs: [AssetRef] = []
    /// Every file of the current query, folded or not.
    private(set) var allRefs: [AssetRef] = []
    /// Image sequences of the folder shown, by head (D-84), and the head of every frame.
    var sequences: [Int64: ImageSequence] = [:]
    var sequenceHeads: [Int64: Int64] = [:]
    /// Heads unfolded in this session.
    var unfoldedSequences: Set<Int64> = []
    /// The sequence folded or unfolded last, for the grid's animation.
    var lastSequenceToggle: (head: Int64, unfolded: Bool)?
    /// Settings → Library → Image Sequences.
    /// Settings → Library → Hide files smaller than (WIN-061); 0 shows every file.
    var minFileBytes: Int64 = 0 {
        didSet {
            if minFileBytes != oldValue {
                reloadQuery()
            }
        }
    }

    var foldsSequences = true {
        didSet {
            if foldsSequences != oldValue {
                findSequences()
            }
        }
    }

    @ObservationIgnored var sequenceTask: Task<Void, Never>?
    /// Paths being added in this session: their roots show their first scan's progress (D-85).
    @ObservationIgnored var pendingAdds: Set<String> = []
    /// Each root's folders as last read, and folders made in this session (shown even while empty, D-86).
    @ObservationIgnored var listings: [Int64: FolderContents] = [:]
    @ObservationIgnored var createdFolders: Set<String> = []
    private(set) var order = OrderedIDs([])
    /// Increments whenever `refs` changes, so the grid reloads cheaply.
    private(set) var refsVersion = 0
    /// True once the first index for the current query has arrived.
    private(set) var isLoaded = false

    var selection = SelectionModel() {
        didSet { selectionChanged() }
    }

    /// Opens the viewer on an asset (set by the app model).
    var onOpenAsset: ((Int64) -> Void)?
    /// Tells the previews about every selection change (set by the app model).
    var onSelectionChange: ((SelectionModel) -> Void)?
    /// Builds the context menu for the selection (set by the app model).
    var makeContextMenu: ((ActionTarget) -> NSMenu?)?
    /// Increments after the app's own file operations: cached rows (paths, names) are stale.
    var rowsVersion = 0
    /// Export to Folder… of an album (set by the app model).
    var onExportAlbum: ((Int64) -> Void)?
    /// The album whose name the sidebar edits (just created).
    var renamingAlbumID: Int64?
    /// Registers an undoable album change with the app's history (set by the app model).
    var onAlbumChange: ((CustomUndo) -> Void)?
    /// Asks the grid to edit an item's name in place (Finder-style); the serial makes repeats count.
    var inlineRenameRequest: (id: Int64, serial: Int)?
    /// A name edited in place was committed (set by the app model).
    var onInlineRename: ((URL, String) -> Void)?
    /// Files dropped on the sidebar Trash (set by the app model).
    var onTrashFiles: (([URL]) -> Void)?
    /// A click or a key in this pane's grid (a split view makes it the active pane).
    var onInteraction: (() -> Void)?
    /// A sequence folded or unfolded (the previews follow; W-89).
    @ObservationIgnored var onSequenceToggle: (() -> Void)?
    /// ⌥-double-click on a song: the window's mini player (set by the app model).
    var onPlayInMiniPlayer: ((Int64) -> Void)?
    /// Makes a folder through the undoable file operations (set by the app model).
    var onCreateFolder: ((URL, String) -> Void)?
    /// Files dropped on a sidebar folder: moved there, or copied with ⌥ (set by the app model).
    var onDropFiles: (([URL], URL, Bool) -> Void)?
    /// Runs an action on the selection (set by the app model).
    var performAction: ((ActionID) -> Void)?
    /// Space, Esc, Return and F for Quick Preview; returns true when the key was used (set by the app model).
    var onQuickPreviewKey: ((QuickPreviewKey) -> Bool)?

    /// Folders unfolded in the list view in this session (D-125).
    @ObservationIgnored var listExpanded: Set<Int64> = []
    /// Increments when the grid should take keyboard focus and show the focused item (back from the viewer).
    private(set) var focusRequest = 0
    /// The window is narrower than the sidebar needs, so it shows as a strip whatever `state.sidebarCollapsed` says;
    /// set by the library window. A request to show the sidebar in such a window widens it (D-128).
    var isWindowNarrow = false
    var sidebarShowRequest = 0
    /// The folded sidebar sliding out over the files; made on first use (the main pane's window only).
    @ObservationIgnored lazy var sidebarPeek = SidebarPeek()
    /// Search (docs/FEATURES.md §12): the text, whether it covers the whole library instead of the folder or album
    /// shown, and requests to focus the field (⌘F). Not saved between launches.
    var searchText = ""
    var searchEverywhere = false
    var searchFocusRequest = 0
    @ObservationIgnored var searchTask: Task<Void, Never>?

    /// Bytes of the shown items and of the selection, for the status bar.
    private(set) var totalBytes: Int64 = 0
    private(set) var selectedBytes: Int64 = 0
    /// Background work shown in the status bar.
    var activity: LibraryIndexer.Activity? {
        indexer.activity
    }

    /// The latest problem to show (non-modal).
    var problem: Problem?

    private let stateStore: ViewStateStore
    private var refsTask: Task<Void, Never>?
    private var folderTasks: [Int64: Task<Void, Never>] = [:]
    private var totalsTask: Task<Void, Never>?
    private var selectionBytesTask: Task<Void, Never>?
    private var pendingRestore: LibraryViewState?

    init(store: LibraryStore, scanner: LibraryScanner, thumbnails: ThumbnailService, stateStore: ViewStateStore) {
        self.store = store
        self.scanner = scanner
        self.thumbnails = thumbnails
        self.stateStore = stateStore
        indexer = LibraryIndexer(scanner: scanner)
        isFollower = false
        state = stateStore.load()
        pendingRestore = state
    }

    /// The second pane of a split view (D-89): its own view state (saved under its own key), the main pane's store,
    /// indexer and thumbnails; roots, trees and albums come from the main pane.
    init(following leader: LibraryModel, stateStore: ViewStateStore) {
        store = leader.store
        scanner = leader.scanner
        thumbnails = leader.thumbnails
        self.stateStore = stateStore
        indexer = leader.indexer
        isFollower = true
        state = stateStore.load()
        pendingRestore = state
    }

    // MARK: Startup

    func start() async {
        connectIndexer()
        Task { [weak self] in
            guard let self else { return }
            do {
                for try await roots in store.observeRoots() {
                    rootsChanged(roots)
                }
            } catch {}
        }
        startAlbums()
        startRootIcons()
        reloadQuery()
    }

    /// A follower's roots (from its leader).
    func setRoots(_ newRoots: [RootFolder]) {
        roots = newRoots
    }

    private func rootsChanged(_ newRoots: [RootFolder]) {
        let newIDs = Set(newRoots.map(\.id))
        for (id, task) in folderTasks where !newIDs.contains(id) {
            task.cancel()
            folderTasks[id] = nil
            indexer.stopWatching(id)
            trees[id] = nil
        }
        for root in newRoots where folderTasks[root.id] == nil {
            folderTasks[root.id] = Task { [weak self] in
                guard let self else { return }
                do {
                    for try await listing in store.observeFolderListing(rootID: root.id) {
                        listings[root.id] = listing
                        let tree = folderTree(listing, root: root)
                        if trees[root.id] == nil, let top = tree?.folder.id {
                            expandedFolders.insert(top)
                        }
                        let showedHere = state.folderID.map { trees[root.id]?.find($0) != nil } ?? false
                        trees[root.id] = tree
                        if state.folderID == nil, let top = tree?.folder.id {
                            select(folderID: top)
                        } else if showedHere, let shown = state.folderID, let tree, tree.find(shown) == nil {
                            // The folder shown lost its last file (or vanished): back to its root (D-78).
                            select(folderID: tree.folder.id)
                        }
                    }
                } catch {}
            }
            indexer.startWatching(root, isNew: pendingAdds.remove(root.path) != nil)
        }
        roots = newRoots
        if let folderID = state.folderID, !trees.isEmpty, folder(id: folderID) == nil, !newRoots.isEmpty {
            // The selected folder vanished with its root: fall back to the first root.
            state.folderID = trees[newRoots[0].id]?.folder.id
            reloadQuery()
        }
        if newRoots.isEmpty, state.folderID != nil {
            state.folderID = nil
            reloadQuery()
        }
    }

    // MARK: Query

    func updateState(_ change: (inout LibraryViewState) -> Void) {
        change(&state)
        stateStore.save(state)
    }

    func reloadQuery() {
        refsTask?.cancel()
        isLoaded = false
        let query = query
        refsTask = Task { [weak self, store] in
            do {
                for try await refs in store.observeAssetRefs(query) {
                    self?.refsChanged(refs)
                }
            } catch {}
        }
        refreshTotals()
    }

    private func refsChanged(_ newRefs: [AssetRef]) {
        allRefs = newRefs
        findSequences()
        showRefs(folded(newRefs))
        isLoaded = true
        if !newRefs.isEmpty {
            LaunchMetrics.markInteractive()
        }
        refreshTotals()
    }

    /// The shown index: `newRefs` as the grid shows them.
    func showRefs(_ newRefs: [AssetRef]) {
        refs = newRefs
        order = OrderedIDs(newRefs.map(\.id))
        if let restore = pendingRestore {
            pendingRestore = nil
            selection.restore(restore.selectedIDs.filter { order.index(of: $0) != nil }, focus: restore.focusedID)
        }
        selection.retain(onlyIn: order)
        refsVersion += 1
    }

    private func refreshTotals() {
        totalsTask?.cancel()
        let query = query
        totalsTask = Task { [weak self, store] in
            guard let totals = try? await store.totals(for: query), !Task.isCancelled else { return }
            self?.totalBytes = totals.bytes
        }
    }

    private func selectionChanged() {
        onSelectionChange?(selection)
        updateState { state in
            let ids = selection.selected
            state.selectedIDs = ids.count <= LibraryViewState.maxSavedSelection ? Array(ids) : []
            state.focusedID = selection.focus
        }
        selectionBytesTask?.cancel()
        let ids = selection.selected
        guard !ids.isEmpty else {
            selectedBytes = 0
            return
        }
        selectionBytesTask = Task { [weak self, store] in
            guard let bytes = try? await store.totalSize(ids: ids), !Task.isCancelled else { return }
            self?.selectedBytes = bytes
        }
    }

    // MARK: Viewer

    /// Selects `assetID` (if shown) and focuses the grid on it.
    func reveal(_ assetID: Int64) {
        if order.index(of: assetID) != nil {
            selection.select(assetID)
        }
        focusGrid()
    }

    func focusGrid() {
        focusRequest += 1
    }
}
