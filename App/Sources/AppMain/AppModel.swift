import AppKit
import Foundation
import JGModel
import JGPlayback
import JGScanner
import JGStore
import JGThumbs
import Observation

/// Owns the app's long-lived services, the player and the viewer; outlives windows (docs/ARCHITECTURE.md §9, §17).
@MainActor
@Observable
final class AppModel {
    /// The viewer filling the window: photos, or video and audio.
    enum Viewer {
        case photo(PhotoViewerModel)
        case media(MediaViewerModel)
        /// Two photos side by side (W-77).
        case compare(CompareModel)
    }

    /// Nil until the databases are open (a few milliseconds after launch).
    private(set) var library: LibraryModel?
    /// Set when the databases cannot be opened.
    private(set) var startupError: String?
    /// The library had to be restored or restarted at launch (shown once as a banner).
    var startupRecovery: LibraryRecovery?
    /// The selection's preview (pane and Quick Preview); nil until the library is ready.
    private(set) var preview: PreviewModel?
    @ObservationIgnored private(set) var quickPreview: QuickPreviewController?
    /// Move, copy, rename, trash with undo; nil until the library is ready.
    private(set) var fileOps: FileOperationsModel?
    /// Settings (appearance, theme, cache, playback, decor).
    let settingsStore = SettingsStore(isPersistent: AppPaths.dataOverride == nil)
    /// Settings → Open With.
    let openWith = OpenWithStore(isPersistent: AppPaths.dataOverride == nil)
    /// Settings → Shortcuts.
    let shortcuts = ShortcutStore(isPersistent: AppPaths.dataOverride == nil)
    /// Flags for stars outside the grid.
    let flagBook = FlagBook()
    /// ⌃F, then a digit.
    @ObservationIgnored private(set) lazy var flagChord = FlagChord(appModel: self)
    /// Runs the actions of the registry (context menus, menu bar).
    /// The split view's second pane (D-89), and whether it is the active one.
    var secondPane: LibraryModel?
    var isSecondPaneActive = false
    /// The mini player at the bottom of the library window (D-88).
    @ObservationIgnored let windowPlayer = WindowPlayerModel()
    /// The size map module's data (D-127).
    @ObservationIgnored let sizeMap = SizeMapModel()
    /// The daily look for a newer version (D-104).
    @ObservationIgnored private(set) lazy var updates = UpdateService(store: settingsStore)
    /// Split into Stems (D-97).
    @ObservationIgnored private(set) lazy var stems = makeStems()
    /// The keyboard's media keys and Now Playing (D-92).
    @ObservationIgnored private(set) lazy var mediaKeys = MediaKeys(appModel: self)
    @ObservationIgnored private(set) lazy var actions = ActionPerformer(appModel: self, openWith: openWith)
    /// The open viewer, if any.
    var viewer: Viewer? {
        didSet { viewerChanged(from: oldValue) }
    }

    /// The one player of the app (docs/ARCHITECTURE.md §9).
    let playback = PlaybackController()
    @ObservationIgnored private(set) var waveforms = WaveformService(disk: nil)
    /// Tempo and key of songs (D-106), kept in the library's database once it is open.
    @ObservationIgnored let analyses = AudioAnalyses()
    @ObservationIgnored private(set) lazy var tuning = PlaybackTuning(
        playback: playback, store: PlaybackPreferencesStore(isPersistent: AppPaths.dataOverride == nil)
    )

    /// Files opened before the library was ready.
    @ObservationIgnored var pendingURLs: [URL] = []
    /// Set by the app delegate when the app was launched by opening files.
    @ObservationIgnored var launchedWithFiles = false
    @ObservationIgnored private var isLaunchDecided = false
    @ObservationIgnored private var launchWaiters: [CheckedContinuation<Void, Never>] = []

    /// Called by the app delegate when launching is over.
    func launchDecided() {
        isLaunchDecided = true
        let waiters = launchWaiters
        launchWaiters = []
        waiters.forEach { $0.resume() }
    }

    /// The viewer alone: launched for a file, the library is not loaded until "‹ Library" (or Add Folder). Closing
    /// the window then quits the app.
    var isViewerOnly = false
    /// The databases, opened once (also in viewer-only mode, to tell whether a file is in the library).
    @ObservationIgnored var stores: (LibraryStore, ThumbnailDiskCache)?
    @ObservationIgnored private var starting: Task<Void, Never>?
    @ObservationIgnored let classifier = MediaClassifier()

    /// The photo viewer, when that is what is open.
    var photoViewer: PhotoViewerModel? {
        if case let .photo(model) = viewer {
            model
        } else {
            nil
        }
    }

    /// The video or audio viewer, when that is what is open.
    var mediaViewer: MediaViewerModel? {
        if case let .media(model) = viewer {
            model
        } else {
            nil
        }
    }

    /// Opens the databases off the main thread, then starts the library. Idempotent: SwiftUI may run the
    /// window's task again (for example when a file opened from Finder launches the app), and a second call
    /// must wait for the first instead of creating a second library.
    func start() async {
        settingsStore.applyTheme()
        // Whether the app was launched for a file is known only when launching is over.
        if !isLaunchDecided {
            await withCheckedContinuation { launchWaiters.append($0) }
        }
        if let starting {
            await starting.value
            return
        }
        if launchedWithFiles, library == nil, !pendingURLs.contains(where: Self.isFolder) {
            isViewerOnly = true
            let pending = pendingURLs
            pendingURLs = []
            _ = try? await openStores()
            await open(pending)
            return
        }
        let task = Task { await performStart() }
        starting = task
        await task.value
    }

    /// "‹ Library" in a viewer opened on its own, or Add Folder there: the library loads behind the viewer.
    func ensureLibrary() async {
        guard library == nil else { return }
        if let starting {
            await starting.value
            return
        }
        let task = Task { await performStart() }
        starting = task
        await task.value
    }

    private func performStart() async {
        do {
            let opened = try await openStores()
            let model = LibraryModel(
                store: opened.0,
                scanner: LibraryScanner(store: opened.0),
                thumbnails: ThumbnailService(disk: opened.1),
                stateStore: ViewStateStore(isPersistent: AppPaths.dataOverride == nil)
            )
            waveforms = WaveformService(disk: opened.1)
            await analyses.setStore(opened.0)
            settingsStore.thumbnailCache = opened.1
            settingsStore.applyAll()
            connectPreview(to: model)
            if viewer != nil {
                // Loaded behind an open viewer: the previews keep their hands off its player.
                preview?.suspend(viewerPlays: mediaViewer != nil)
            }
            _ = flagChord
            let fileOps = FileOperationsModel(store: opened.0, isPersistent: AppPaths.dataOverride == nil)
            fileOps.onFilesChanged = { [weak self, weak model] in
                model?.filesChanged()
                self?.secondPane?.filesChanged()
                self?.preview?.reload()
            }
            self.fileOps = fileOps
            settingsStore.onChange = { [weak self] settings in self?.apply(settings) }
            updates.scheduleDailyCheck()
            library = model
            // After `library` is set: the settings go into the panes (grid animation, sequences, decor).
            apply(settingsStore.settings)
            restoreSplit()
            await model.start()
            let pending = pendingURLs
            pendingURLs = []
            await open(pending)
        } catch {
            startupError = String(describing: error)
        }
    }

    // MARK: Viewer

    /// Back to the library, with the last viewed file selected and in view.
    func closeViewer() {
        if isViewerOnly {
            // "‹ Library" from a viewer opened on its own: from now on the app is the whole app.
            isViewerOnly = false
            Task {
                await ensureLibrary()
                closeViewer()
            }
            return
        }
        let assetID: Int64? = switch viewer {
        case let .photo(model): model.currentPhoto?.assetID
        case let .media(model): model.current?.assetID
        case let .compare(model): model.leftAssetID
        case nil: nil
        }
        if let assetID {
            activeLibrary?.reveal(assetID)
        } else {
            activeLibrary?.focusGrid()
        }
        viewer = nil
    }

    /// Playback stops when the video or audio viewer goes away (until background mode, Phase 11). The previews
    /// stand aside while a viewer is open and come back after it.
    private func viewerChanged(from old: Viewer?) {
        if case let .media(oldModel) = old, mediaViewer !== oldModel, mediaViewer == nil {
            oldModel.close()
        }
        if case let .compare(oldModel) = old, compareModel !== oldModel {
            oldModel.close()
        }
        if viewer != nil, old == nil {
            quickPreview?.close()
            preview?.suspend(viewerPlays: mediaViewer != nil)
        } else if viewer == nil, old != nil {
            preview?.resume()
        }
    }

    /// The preview follows the library's selection; Space, Esc and Return drive Quick Preview.
    private func connectPreview(to library: LibraryModel) {
        let preview = PreviewModel(
            store: library.store, thumbnails: library.thumbnails, waveforms: { [weak self] in
                self?.waveforms ?? WaveformService(disk: nil)
            }, tuning: tuning
        )
        let quickPreview = QuickPreviewController(preview: preview, settings: settingsStore, flagBook: flagBook)
        self.preview = preview
        self.quickPreview = quickPreview
        connectPane(library)
        quickPreview.onOpenInViewer = { [weak self] in self?.openFromQuickPreview() }
        // A folded image sequence previews as a timeline of its frames (W-86).
        preview.foldedSequence = { [weak self] id in
            guard let library = self?.activeLibrary, library.isFolded(id) else { return nil }
            return library.sequence(headedBy: id)?.frames
        }
        quickPreview.onInfo = { [weak self, weak preview] in
            guard let self, let asset = preview?.asset else { return }
            let url = asset.url
            // Files outside the library have negative ids (never stored).
            actions.perform(.getInfo, on: ActionTarget(
                place: .viewer, assetIDs: asset.id > 0 ? [asset.id] : [], kinds: [asset.kind], count: 1, sample: url,
                urls: { [url] }
            ))
        }
    }

    /// Longest side, in device pixels, of the largest screen: the size of screen-size decodes.
    static var screenPixels: Int {
        let sides = NSScreen.screens.map { max($0.frame.width, $0.frame.height) * $0.backingScaleFactor }
        return Int(sides.max() ?? 2560)
    }
}
