import AppKit
import JGActions
import JGModel
import JGScanner
import JGSettings

/// Launch-argument hooks for benchmarks and visual checks; inert without the arguments.
///
/// - `-JGDataDirectory <dir>`: separate library and cache (see `AppPaths`); state is not persisted.
/// - `-JGAddFolder <path>`: adds the folder on start (if needed) and waits until it is indexed.
/// - `-JGAppearance dark|light`: forces the appearance.
/// - `-JGPreset performance|beauty`, `-JGKindFilters labels|icons`, `-JGPreviewDetails YES`: settings for the run.
/// - `-JGTileSide <points>`, `-JGSelect <count>`: tile size and a selection of the first items.
/// - `-JGViewMode grid|list` (`-JGListExpand YES`: every folder row unfolded): the library's view (D-125).
/// - `-JGSizeMap bottom|right`: shows the size map there (D-127).
/// - `-JGSidebar docked|collapsed|peek`: the sidebar docked, folded into its strip, or out over the files (D-128).
/// - `-JGSidebarSample YES` (`-JGRootIcon <emoji | sf:symbol | /path>`): two albums and the first folder's icon (D-129).
/// - `-JGWindowWidth <points>`: the main window's width. `-JGSearch <text>` (`-JGSearchEverywhere YES`): a search.
/// - `-JGOpen <path>`: opens a file or folder as if from Finder.
/// - `-JGServiceLaunch <file>`: a launch by Finder ▸ Services ▸ Quick Preview (see `ServiceLaunchCheck`).
/// - `-JGLaunchLog <file>`: writes the launch mode, then closes the window (see `LaunchCheck`).
/// - `-JGViewerOnly <file>`: launches as if Finder opened the file (the viewer alone, no library).
/// - `-JGPlaybackState YES`: logs the player's state after `-JGOpen`.
/// - `-JGMute YES`: mutes the player (silent snapshot and benchmark runs).
/// - `-JGSnapshot <file.png>`: renders the main window to a PNG, then quits.
/// - `-JGSnapshotSize <W>x<H>`: the snapshot draws the main window's content offscreen at that size (a window tiled to
///   half the screen keeps its size against `-JGWindowWidth`).
/// - `-JGPrintMenu YES`: prints the context menu of the viewer's file or the selection to stderr.
/// - `-JGFileOpsCheck <folder>`: photos only, select all, Move to the folder, Undo; logs each step, then quits.
///   Use only on copies of test media.
/// - `-JGAlbumCheck <folder>`: an album from every photo, a member moved into the folder, Remove from Album and
///   undo; logs each step (combine with -JGSnapshot). Test copies only.
/// - `-JGSnapshotSettings <folder>`: renders every Settings section to settings-N.png there.
/// - `-JGAbout YES`: opens the About panel (snapshot it with `-JGSnapshotPanel`).
/// - `-JGOnboarding YES`: shows the first-launch choice of a look.
/// - `-JGFilmstripRevealCheck <folder>`: pointer near the bottom and away again, a snapshot of each (automatic strip).
/// - `-JGResizeBenchmark`: window resize steps with the library and each viewer, in milliseconds.
/// - `-JGWindowControlsCheck`: the window buttons' place, a viewer in a smaller window, the see-through photo viewer.
/// - `-JGFlagRedrawCheck <png>`: three tiles flagged; the grid snapshotted 150 ms later.
/// - `-JGZoomStep <points>` with `-JGZoomBenchmark`: a fast ruler drag of big steps.
/// - `-JGMusicCheck <png>`: the first song's tempo and key, a target pitch and tempo, the panel (logged, muted).
/// - `-JGMiniPlayerCheck <png>`: the mini player paused by the full player and resumed (logged, muted).
/// - `-JGCompareCheck <png>`: Compare on the first two photos at fit and 100 % (a snapshot of each), then swap, unlink
///   and back (logged).
/// - `-JGDuplicatesCheck <png>`: Find Duplicates (snapshot, logged), then Move to Trash with the Trash only logged.
/// - `-JGQuickPreviewOpenCheck YES` (with `-JGSelect 1`): Quick Preview's level, then Open in Viewer (logged).
/// - `-JGSequencePreviewCheck <png>`: the preview's frame timeline of a folded sequence (drag, play, unfold; logged).
/// - `-JGStemCheck <png>` with `-JGStemModels <folder>`: Split into Stems on the first song (logged; never undone).
/// - `-JGThemeCheck <png>`: the Black theme, a chosen accent and Light, live, a snapshot of each.
/// - `-JGUpdateCheck YES` (`-JGUpdateInstalled <x.y.z>`): the update check at once, as Check Now does (logged).
/// - `-JGSplitCheck <png>`: split view side by side and stacked (a snapshot of each), then off (logged).
/// - `-JGSizeMapCheck <png>`: the size map moved between its places with a selection, and across folders (logged).
/// - `-JGPinDeepest YES`: pins the deepest folder of the first root.
/// - `-JGNewFolderCheck <name>`: makes an empty folder in the first root and logs the sidebar's subfolders.
/// - `-JGAddingCheck <folder>` (`-JGAddingSnapshot <png>`): adds a folder and logs its first scan's progress.
/// - `-JGSequenceCheck <snapshot.png>`: unfolds the first image sequence, snapshots, folds it back (logged).
/// - `-JGReflowCheck YES`: a tile-size change mid-glide and the anchor tile, logged (`ReflowCheck`).
/// - `-JGSegmentCheck <folder>` with `-JGOpen`: segment selection, zoom and export in the open player (`SegmentCheck`).
/// - `-JGSwipeCheck <folder>` (`-JGSwipeInput drag|trackpad`): a synthetic swipe in the open viewer, snapshotted.
/// - `-JGFlagCheck YES` (with `-JGSelect N`): flags by ⌃1, the star filter, undo; logged. Test libraries only.
/// - `-JGBatchRenameCheck <snapshot.png>` (with `-JGSelect N`): batch rename and undo; logged. Test copies only.
/// - `-JGFinderPreviewCheck <file>`: the Finder service with the file, then → (snapshot with `-JGSnapshotPanel`).
/// - `-JGPreviewToggleCheck YES`: presses ⌥⌘0 twice and logs the preview pane's visibility.
/// - `-JGInlineRename YES`: starts renaming the focused tile in place.
/// - `-JGGetInfo YES`: shows Get Info for the viewer's file or the selection (`-JGSnapshotInfo <file.png>` renders it).
/// - `-JGQuickPreview YES`: opens Quick Preview on the selection; `-JGSnapshotPanel <file.png>` renders it too;
///   `-JGQuickPreviewFullScreen YES` then presses F twice (full screen on, off) and logs each state.
/// - `-JGScrollBenchmark <file.json>` (`-JGScrollSpeed`): thumbnails under a fast scroll and after it (`ScrollBenchmark`).
/// - `-JGZoomBenchmark <file.json>`: a ruler drag on the tile size, tick gaps and CPU (`ZoomBenchmark`).
/// - `-JGBenchmark <file.json>`: runs `Benchmark`, writes the results, then quits.
/// - `-JGViewerBenchmark <file.json>` with `-JGOpen <photo in the library>` (and optionally `-JGOutsideFile <path>`):
///   runs `ViewerBenchmark`, then quits.
/// - `-JGPlaybackBenchmark <file.json>` with `-JGOpen <video>` (and optionally `-JGAudioFile <path>`):
///   runs `PlaybackBenchmark`, then quits.
@MainActor
enum DeveloperHooks {
    static let defaults = UserDefaults.standard

    static var isActive: Bool {
        [
            "JGAddFolder",
            "JGSnapshot",
            "JGBenchmark",
            "JGScrollBenchmark",
            "JGZoomBenchmark",
            "JGAppearance",
            "JGOpen",
            "JGViewerOnly",
            "JGLaunchLog",
            "JGServiceLaunch",
        ]
        .contains { defaults.object(forKey: $0) != nil }
    }

    private static var hasRun = false

    static func run(_ appModel: AppModel) async {
        guard isActive, !hasRun else { return }
        if await runLaunchChecks(appModel) {
            return
        }
        guard let library = appModel.library else { return }
        hasRun = true
        await prepare(library, appModel)
        if let path = defaults.string(forKey: "JGOpen") {
            await open(URL(fileURLWithPath: path), appModel)
        }
        if defaults.bool(forKey: "JGPlaybackState") {
            await logPlaybackState(appModel)
        }
        if let output = defaults.string(forKey: "JGZoomBenchmark") {
            await ZoomBenchmark.run(library: library, output: URL(fileURLWithPath: output))
        }
        if let output = defaults.string(forKey: "JGScrollBenchmark") {
            await ScrollBenchmark.run(library: library, output: URL(fileURLWithPath: output))
        }
        if let output = defaults.string(forKey: "JGBenchmark") {
            await Benchmark.run(library: library, output: URL(fileURLWithPath: output))
            NSApp.terminate(nil)
        }
        await runInspectionHooks(appModel, library)
        if defaults.bool(forKey: "JGQuickPreview") {
            await openQuickPreview(appModel)
        }
        await snapshotAndQuit(appModel)
    }

    /// `-JGPlaybackState YES` with `-JGOpen <video or audio>`: the player's state twice, 0.5 s and 1.5 s after opening.
    private static func logPlaybackState(_ appModel: AppModel) async {
        for delay in [500, 1000] {
            try? await Task.sleep(for: .milliseconds(delay))
            let playback = appModel.playback
            let state = "status \(playback.status), playing \(playback.isPlaying), time \(String(format: "%.2f", playback.currentTime)), "
                + "duration \(playback.duration ?? -1), size \(playback.info?.videoSize ?? .zero), "
                + "matroska picture \(playback.matroskaLayer != nil)"
            FileHandle.standardError.write(Data("playback state: \(state)\n".utf8))
        }
    }

    /// `-JGOpen`: a viewer or player benchmark on the file (then quits), or just opening it.
    private static func open(_ url: URL, _ appModel: AppModel) async {
        if let output = defaults.string(forKey: "JGViewerBenchmark") {
            await ViewerBenchmark.run(
                appModel: appModel, libraryFile: url,
                outsideFile: defaults.string(forKey: "JGOutsideFile").map { URL(fileURLWithPath: $0) },
                output: URL(fileURLWithPath: output)
            )
            NSApp.terminate(nil)
        } else if let output = defaults.string(forKey: "JGPlaybackBenchmark") {
            await PlaybackBenchmark.run(
                appModel: appModel, video: url, audio: defaults.string(forKey: "JGAudioFile").map { URL(fileURLWithPath: $0) },
                output: URL(fileURLWithPath: output)
            )
            NSApp.terminate(nil)
        } else {
            await appModel.open([url])
        }
    }

    /// Launches without a library behind them: the Finder service, the launch log, a startup error, the viewer alone.
    /// True when one of them ran.
    private static func runLaunchChecks(_ appModel: AppModel) async -> Bool {
        if let file = defaults.string(forKey: "JGServiceLaunch") {
            hasRun = true
            await ServiceLaunchCheck.run(appModel, file: URL(fileURLWithPath: file))
            return true
        }
        if let log = defaults.string(forKey: "JGLaunchLog") {
            await LaunchCheck.run(appModel, log: URL(fileURLWithPath: log))
            return true
        }
        if appModel.startupError != nil {
            hasRun = true
            await snapshotAndQuit(appModel)
            return true
        }
        if appModel.isViewerOnly, appModel.library == nil {
            // `-JGViewerOnly <file>`: settings, the snapshot, and `-JGViewerOnlyLibrary YES` ("‹ Library").
            hasRun = true
            applySettings(appModel)
            if defaults.bool(forKey: "JGViewerOnlyLibrary") {
                await ViewerOnlyCheck.run(appModel)
            }
            await snapshotAndQuit(appModel)
            return true
        }
        return false
    }

    /// -JGPrintMenu, -JGFileOpsCheck, -JGInlineRename, -JGGetInfo.
    private static func runInspectionHooks(_ appModel: AppModel, _ library: LibraryModel) async {
        if defaults.bool(forKey: "JGPrintMenu") {
            try? await Task.sleep(for: .milliseconds(500))
            let menu = appModel.viewerContextMenu()
                ?? library.actionTarget(sample: appModel.preview?.asset?.url).flatMap { library.makeContextMenu?($0) }
            FileHandle.standardError.write(Data((menu.map { describe($0, indent: "") } ?? "no menu\n").utf8))
        }
        if let folder = defaults.string(forKey: "JGFileOpsCheck") {
            await FileOpsCheck.run(appModel: appModel, library: library, destination: URL(fileURLWithPath: folder, isDirectory: true))
            NSApp.terminate(nil)
        }
        if let folder = defaults.string(forKey: "JGAlbumCheck") {
            await AlbumCheck.run(appModel: appModel, library: library, moveInto: URL(fileURLWithPath: folder, isDirectory: true))
        }
        if let folder = defaults.string(forKey: "JGSnapshotSettings") {
            await snapshotSettings(appModel, to: URL(fileURLWithPath: folder, isDirectory: true))
        }
        if defaults.bool(forKey: "JGAbout") {
            AboutPanel.show(store: appModel.settingsStore)
        }
        if defaults.bool(forKey: "JGOnboarding") {
            appModel.settingsStore.update { $0.hasChosenAppearance = false }
        }
        await runInteractionChecks(appModel, library)
        if defaults.bool(forKey: "JGInlineRename"), let id = library.selection.focus {
            try? await Task.sleep(for: .milliseconds(500))
            library.requestInlineRename(id)
        }
        if defaults.bool(forKey: "JGGetInfo") {
            await getInfo(appModel, library)
        }
    }

    /// -JGGetInfo (and -JGSnapshotInfo).
    private static func getInfo(_ appModel: AppModel, _ library: LibraryModel) async {
        // The viewer's row loads a moment after it opens.
        for _ in 0 ..< 20 where appModel.currentTarget == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        guard let target = appModel.currentTarget else { return }
        appModel.actions.perform(.getInfo, on: target)
        if let output = defaults.string(forKey: "JGSnapshotInfo") {
            await snapshotInfo(target, library: library, to: URL(fileURLWithPath: output))
        }
    }

    /// Appearance, folder, tile size and selection from the launch arguments.
    private static func prepare(_ library: LibraryModel, _ appModel: AppModel) async {
        applySettings(appModel)
        if let path = defaults.string(forKey: "JGAddFolder") {
            let existing = await (try? library.store.roots()) ?? []
            if !existing.contains(where: { $0.path == CanonicalPath.of(URL(fileURLWithPath: path)) }) {
                await library.addFolders([URL(fileURLWithPath: path)])
            }
            await waitUntilIdle(library)
        }
        let side = defaults.double(forKey: "JGTileSide")
        if side > 0 {
            library.setTileSide(side)
        }
        applyViewMode(library)
        let width = defaults.double(forKey: "JGWindowWidth")
        if width > 0, let window = mainWindow {
            window.setContentSize(NSSize(width: width, height: window.contentLayoutRect.height))
        }
        if let text = defaults.string(forKey: "JGSearch") {
            library.setSearchEverywhere(defaults.bool(forKey: "JGSearchEverywhere"))
            library.requestSearchFocus()
            library.setSearch(text)
            try? await Task.sleep(for: .milliseconds(400))
        }
        let selectCount = defaults.integer(forKey: "JGSelect")
        if selectCount > 0 {
            var selection = SelectionModel()
            selection.restore(library.refs.prefix(selectCount).map(\.id), focus: library.refs.first?.id)
            library.selection = selection
        }
    }

    /// Mute, appearance and settings for the run.
    private static func applySettings(_ appModel: AppModel) {
        if defaults.bool(forKey: "JGMute") {
            // Every player: checks play silently.
            appModel.playback.isMuted = true
            appModel.windowPlayer.playback.isMuted = true
        }
        if let preset = defaults.string(forKey: "JGPreset").flatMap(AppearancePreset.init(rawValue:)) {
            appModel.settingsStore.update { preset.apply(to: &$0) }
        }
        if defaults.bool(forKey: "JGPreviewDetails") {
            appModel.settingsStore.update { $0.previewDetails = true }
        }
        if let style = defaults.string(forKey: "JGKindFilters").flatMap(KindFilterStyle.init(rawValue:)) {
            appModel.settingsStore.update { $0.kindFilterStyle = style }
        }
        if let appearance = defaults.string(forKey: "JGAppearance") {
            NSApp.appearance = NSAppearance(named: appearance == "light" ? .aqua : .darkAqua)
        }
    }

    /// A menu as text: titles, shortcut hints, disabled items in brackets, submenus indented.
    private static func describe(_ menu: NSMenu, indent: String) -> String {
        menu.items.map { item in
            if item.isSeparatorItem {
                return indent + "---\n"
            }
            let modifiers = item.keyEquivalentModifierMask.rawValue >> 16
            let key = item.keyEquivalent.isEmpty ? "" : "  [\(modifiers)+\(item.keyEquivalent.debugDescription)]"
            let title = item.isEnabled ? item.title : "(\(item.title))"
            return indent + title + key + "\n" + (item.submenu.map { describe($0, indent: indent + "    ") } ?? "")
        }.joined()
    }

    static var mainWindow: NSWindow? {
        NSApp.windows.first { !($0 is NSPanel) && $0.isVisible && $0.contentView != nil && $0.frame.width >= 400 }
    }

    /// Waits until indexing and metadata extraction are done and the index is loaded.
    static func waitUntilIdle(_ library: LibraryModel) async {
        var stableChecks = 0
        while stableChecks < 3 {
            try? await Task.sleep(for: .milliseconds(200))
            stableChecks = (library.activity == nil && library.isLoaded && !library.roots.isEmpty) ? stableChecks + 1 : 0
        }
    }

    /// Renders the window content (including AppKit layers) without screen-recording permission.
    static func snapshot(_ window: NSWindow, to url: URL) {
        guard let view = window.contentView else { return }
        guard let layer = view.layer else {
            // Views without a layer (a hosting controller's view): AppKit's own drawing.
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: url)
            }
            return
        }
        let scale = window.backingScaleFactor
        let size = view.bounds.size
        guard let context = CGContext(
            data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return }
        // CGContext's origin is bottom-left; the window content is drawn top-down.
        context.translateBy(x: 0, y: size.height * scale)
        context.scaleBy(x: scale, y: -scale)
        layer.render(in: context)
        guard let image = context.makeImage() else { return }
        try? NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])?.write(to: url)
    }
}

extension DeveloperHooks {
    /// `-JGSnapshot`: the main window (and `-JGSnapshotPanel`: a visible panel) to PNG, then quits; with
    /// `-JGSnapshotSize WxH` the window's content drawn offscreen at that size instead.
    static func snapshotAndQuit(_ appModel: AppModel) async {
        if let output = defaults.string(forKey: "JGSnapshot") {
            let delay = defaults.double(forKey: "JGSnapshotDelay")
            try? await Task.sleep(for: .seconds(delay > 0 ? delay : 2))
            if let panelOutput = defaults.string(forKey: "JGSnapshotPanel"),
               let panel = NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible })
            {
                snapshot(panel, to: URL(fileURLWithPath: panelOutput))
            }
            if let size = defaults.string(forKey: "JGSnapshotSize") {
                await OffscreenSnapshot.run(appModel, size: size, to: URL(fileURLWithPath: output))
            } else if let window = mainWindow {
                snapshot(window, to: URL(fileURLWithPath: output))
            }
            NSApp.terminate(nil)
        }
    }

    /// `-JGViewMode grid|list`, with `-JGListExpand YES` every folder row unfolded (D-125).
    static func applyViewMode(_ library: LibraryModel) {
        // `-JGSidebar docked|collapsed|peek`: the sidebar, its strip, or the strip with the sidebar out over the files.
        if let sidebar = defaults.string(forKey: "JGSidebar") {
            library.setSidebarCollapsed(sidebar != "docked")
            if sidebar == "peek" {
                library.sidebarPeek.open()
            }
        }
        // `-JGSizeMap bottom|right`: the size map shown in that place (D-127).
        if let slot = defaults.string(forKey: "JGSizeMap").flatMap(ModuleSlot.init(rawValue:)) {
            library.setModuleVisible(.sizeMap, true)
            if library.state.slot(of: .sizeMap) != slot {
                library.moveModule(.sizeMap)
            }
        }
        guard let mode = defaults.string(forKey: "JGViewMode").flatMap(LibraryViewState.ViewMode.init(rawValue:)) else { return }
        if defaults.bool(forKey: "JGListExpand") {
            library.listExpanded = Set(library.trees.values.flatMap { folderIDs(in: $0) })
        }
        library.setViewMode(mode)
    }

    /// Every folder id of a tree.
    private static func folderIDs(in node: FolderNode) -> [Int64] {
        [node.id] + (node.children ?? []).flatMap(folderIDs)
    }
}
