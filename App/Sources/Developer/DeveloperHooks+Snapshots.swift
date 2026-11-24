import AppKit
import JGActions
import JGDesign
import SwiftUI

/// Snapshots of views that live outside the main window (Settings, Get Info) and the synthetic-input checks.
extension DeveloperHooks {
    /// Every Settings section to settings-N.png in `folder`.
    static func snapshotSettings(_ appModel: AppModel, to folder: URL) async {
        for (index, section) in SettingsSection.allCases.enumerated() {
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: JGMetrics.settingsWidth, height: JGMetrics.settingsHeight),
                styleMask: [.titled], backing: .buffered, defer: false
            )
            window.contentView = NSHostingView(rootView: SettingsView(appModel: appModel, section: section)
                .appSettings(appModel.settingsStore))
            window.orderFront(nil)
            try? await Task.sleep(for: .milliseconds(500))
            snapshot(window, to: folder.appendingPathComponent("settings-\(index).png"))
            window.orderOut(nil)
        }
    }

    /// Get Info's content in a window of its own (the panel hides while the app is not active, as in hook runs).
    static func snapshotInfo(_ target: ActionTarget, library: LibraryModel, to url: URL) async {
        let assets = await (try? library.store.assets(ids: target.assetIDs)) ?? []
        let controller = NSHostingController(rootView: InfoView(entries: assets.map(InfoEntry.init(asset:))))
        controller.sizingOptions = .preferredContentSize
        let window = NSWindow(contentViewController: controller)
        window.styleMask = [.titled]
        window.orderFront(nil)
        try? await Task.sleep(for: .milliseconds(1200))
        snapshot(window, to: url)
        window.orderOut(nil)
    }

    /// -JGFilmstripRevealCheck, -JGSwipeCheck, -JGPreviewToggleCheck: synthetic input in the open viewer or library.
    /// Adding a folder, image sequences, the reflow animation.
    private static func runGridChecks(_ library: LibraryModel) async {
        // `-JGPinDeepest YES`: pins the deepest folder of the first root (for a snapshot of the PINNED section).
        if defaults.bool(forKey: "JGPinDeepest"), let root = library.roots.first, var node = library.trees[root.id] {
            while let child = node.children?.first {
                node = child
            }
            library.pin(node.folder)
        }
        if let name = defaults.string(forKey: "JGNewFolderCheck") {
            await ReflowCheck.newFolder(named: name, library: library)
        }
        if let folder = defaults.string(forKey: "JGAddingCheck") {
            await ReflowCheck.addFolderWatchingProgress(
                URL(fileURLWithPath: folder), library: library, window: mainWindow,
                snapshot: defaults.string(forKey: "JGAddingSnapshot").map { URL(fileURLWithPath: $0) }
            )
        }
        if let snapshot = defaults.string(forKey: "JGSequenceCheck") {
            await ReflowCheck.unfoldFirstSequence(library: library, window: mainWindow, snapshot: URL(fileURLWithPath: snapshot))
        }
        if defaults.bool(forKey: "JGReflowCheck") {
            await ReflowCheck.run(library: library, window: mainWindow)
        }
    }

    static func runInteractionChecks(_ appModel: AppModel, _ library: LibraryModel) async {
        if let folder = defaults.string(forKey: "JGFilmstripRevealCheck") {
            await FilmstripRevealCheck.run(window: mainWindow, folder: URL(fileURLWithPath: folder, isDirectory: true))
        }
        if let folder = defaults.string(forKey: "JGSwipeCheck") {
            await SwipeCheck.run(
                appModel: appModel, window: mainWindow, folder: URL(fileURLWithPath: folder, isDirectory: true),
                input: defaults.string(forKey: "JGSwipeInput") ?? "drag"
            )
        }
        if let folder = defaults.string(forKey: "JGSegmentCheck") {
            await SegmentCheck.run(appModel: appModel, window: mainWindow, folder: URL(fileURLWithPath: folder, isDirectory: true))
        }
        await runGridChecks(library)
        await runWindowChecks(appModel, library)
        if defaults.bool(forKey: "JGFlagCheck") {
            await FlagCheck.run(appModel: appModel, library: library)
            await FlagCheck.leaveRedFlags(appModel: appModel, library: library)
        }
        if let output = defaults.string(forKey: "JGBatchRenameCheck") {
            await BatchRenameCheck.run(appModel: appModel, library: library, snapshot: URL(fileURLWithPath: output))
        }
        if let file = defaults.string(forKey: "JGFinderPreviewCheck") {
            await FinderPreviewCheck.run(
                appModel: appModel, delegate: NSApp.servicesProvider as? AppDelegate, file: URL(fileURLWithPath: file)
            )
        }
        if defaults.bool(forKey: "JGPreviewToggleCheck") {
            if defaults.bool(forKey: "JGRemapPreview") {
                _ = appModel.shortcuts.update { $0.assign(ActionShortcut("p", [.command, .control]), to: .togglePreview) }
            }
            await PreviewToggleCheck.run(library: library, shortcuts: appModel.shortcuts, window: mainWindow)
        }
    }

    /// `-JGQuickPreview YES` (with `-JGQuickPreviewSize 420x300` for a small panel, `-JGQuickPreviewFullScreen YES`).
    static func openQuickPreview(_ appModel: AppModel) async {
        try? await Task.sleep(for: .milliseconds(300))
        appModel.quickPreview?.open(over: mainWindow)
        if let size = defaults.string(forKey: "JGQuickPreviewSize")?.split(separator: "x").compactMap({ Double($0) }), size.count == 2,
           let panel = NSApp.windows.first(where: { $0 is NSPanel && $0.isVisible })
        {
            panel.setContentSize(NSSize(width: size[0], height: size[1]))
        }
        if defaults.bool(forKey: "JGQuickPreviewFullScreen") {
            await pressFullScreenKey(appModel)
        }
    }

    /// F on the grid, as the keyboard would send it, twice: full screen on, then off; each state is logged.
    static func pressFullScreenKey(_ appModel: AppModel) async {
        guard let grid = mainWindow?.contentView.flatMap(PreviewToggleCheck.collectionView(in:)),
              let press = NSEvent.keyEvent(
                  with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0, windowNumber: mainWindow?.windowNumber ?? 0,
                  context: nil, characters: "f", charactersIgnoringModifiers: "f", isARepeat: false, keyCode: 3
              )
        else { return }
        for _ in 1 ... 2 {
            try? await Task.sleep(for: .milliseconds(500))
            grid.keyDown(with: press)
            try? await Task.sleep(for: .seconds(2))
            let state = appModel.quickPreview?.isFullScreen == true ? "full screen" : "windowed"
            FileHandle.standardError.write(Data("quick preview after F: \(state)\n".utf8))
        }
    }

    /// -JGResizeBenchmark, -JGWindowControlsCheck, -JGFlagRedrawCheck, -JGMusicCheck.
    private static func runPlayerChecks(_ appModel: AppModel, _ library: LibraryModel) async {
        if defaults.bool(forKey: "JGResizeBenchmark") {
            await ResizeBenchmark.run(appModel, library: library)
        }
        if let snapshot = defaults.string(forKey: "JGFlagRedrawCheck") {
            await FlagRedrawCheck.run(appModel, library: library, snapshot: URL(fileURLWithPath: snapshot))
        }
        if defaults.bool(forKey: "JGWindowControlsCheck") {
            await WindowControlsCheck.run(appModel, library: library)
        }
        if let snapshot = defaults.string(forKey: "JGMusicCheck") {
            await MusicCheck.run(appModel, library: library, snapshot: URL(fileURLWithPath: snapshot))
        }
    }

    /// -JGMiniPlayerCheck, -JGCompareCheck, -JGSplitCheck, -JGSizeMapCheck.
    private static func runWindowChecks(_ appModel: AppModel, _ library: LibraryModel) async {
        if defaults.bool(forKey: "JGUpdateCheck") {
            await appModel.updates.check(manual: true)
            FileHandle.standardError
                .write(Data("update check: \(appModel.updates.status), offer \(appModel.updates.offer?.id ?? "-")\n".utf8))
            try? await Task.sleep(for: .milliseconds(800))
        }
        if let snapshot = defaults.string(forKey: "JGThemeCheck") {
            await ThemeCheck.run(appModel, snapshot: URL(fileURLWithPath: snapshot))
        }
        if let snapshot = defaults.string(forKey: "JGStemCheck") {
            await StemCheck.run(appModel, library: library, snapshot: URL(fileURLWithPath: snapshot))
        }
        if let snapshot = defaults.string(forKey: "JGSequencePreviewCheck") {
            await SequencePreviewCheck.run(appModel, library: library, snapshot: URL(fileURLWithPath: snapshot))
        }
        if defaults.bool(forKey: "JGQuickPreviewOpenCheck") {
            await QuickPreviewOpenCheck.run(appModel)
        }
        if let snapshot = defaults.string(forKey: "JGMiniPlayerCheck") {
            await ReflowCheck.miniPlayer(appModel, library: library, snapshot: URL(fileURLWithPath: snapshot))
        }
        if let snapshot = defaults.string(forKey: "JGCompareCheck") {
            await CompareCheck.run(appModel, library: library, snapshot: URL(fileURLWithPath: snapshot))
        }
        if let snapshot = defaults.string(forKey: "JGDuplicatesCheck") {
            await DuplicatesCheck.run(appModel, library: library, snapshot: URL(fileURLWithPath: snapshot))
        }
        await runPlayerChecks(appModel, library)
        if let snapshot = defaults.string(forKey: "JGSplitCheck") {
            await SplitCheck.run(appModel, library: library, snapshot: URL(fileURLWithPath: snapshot))
        }
        await runSidebarChecks(appModel, library)
    }

    /// -JGSidebarSample, -JGSidebarMorph, -JGSizeMapCheck, -JGSidebarHitCheck.
    private static func runSidebarChecks(_ appModel: AppModel, _ library: LibraryModel) async {
        if defaults.bool(forKey: "JGSidebarSample") {
            await SidebarSample.run(library)
        }
        if let output = defaults.string(forKey: "JGSidebarMorph"), let size = defaults.string(forKey: "JGSnapshotSize") {
            await SidebarSample.morph(appModel, library, size: size, to: URL(fileURLWithPath: output))
        }
        if let snapshot = defaults.string(forKey: "JGSizeMapCheck") {
            await SizeMapCheck.run(appModel, library: library, snapshot: URL(fileURLWithPath: snapshot))
        }
        if defaults.bool(forKey: "JGSidebarHitCheck") {
            await SidebarSample.hitCheck(library)
        }
    }
}
