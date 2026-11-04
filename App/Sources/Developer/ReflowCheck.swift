import AppKit

/// `-JGReflowCheck YES` (with `-JGPreset beauty`): changes the tile size and logs, 0.1 s later, where the first
/// visible tile is drawn against where it will end, and whether the anchor tile kept its place on screen.
@MainActor
enum ReflowCheck {
    static func run(library: LibraryModel, window: NSWindow?) async {
        try? await Task.sleep(for: .milliseconds(800))
        guard let grid = window?.contentView.flatMap(find), let controller = grid.controller else {
            log("no grid")
            return
        }
        let anchor = controller.reflowAnchor()
        library.setTileSide(library.state.tileSide + 80)
        try? await Task.sleep(for: .milliseconds(100))
        if let item = grid.visibleItems().first(where: { $0.view.frame.intersects(grid.visibleRect) }), let layer = item.view.layer {
            let drawn = layer.presentation()?.frame ?? .zero
            let final = item.view.frame
            log("mid-glide: drawn \(Int(drawn.width))×\(Int(drawn.height)) at \(Int(drawn.minX)),\(Int(drawn.minY))")
            log("final \(Int(final.width))×\(Int(final.height)) at \(Int(final.minX)),\(Int(final.minY))")
        }
        try? await Task.sleep(for: .milliseconds(400))
        if let anchor, let after = controller.reflowAnchor() {
            log("anchor tile \(anchor.index) offset \(Int(anchor.offset)) → tile \(after.index) offset \(Int(after.offset))")
        }
    }

    /// `-JGSequenceCheck <snapshot.png>`: unfolds the first image sequence, logs the tiles, snapshots, folds it back.
    static func unfoldFirstSequence(library: LibraryModel, window: NSWindow?, snapshot: URL) async {
        try? await Task.sleep(for: .milliseconds(800))
        guard let head = library.sequences.keys.min(), let window else {
            log("no sequence")
            return
        }
        log("folded: \(library.refs.count) tiles of \(library.allRefs.count) files")
        library.toggleSequence(head)
        try? await Task.sleep(for: .milliseconds(600))
        log("unfolded: \(library.refs.count) tiles")
        DeveloperHooks.snapshot(window, to: snapshot)
        library.toggleSequence(head)
        try? await Task.sleep(for: .milliseconds(600))
        log("folded again: \(library.refs.count) tiles")
    }

    /// `-JGAddingCheck <folder>` (with `-JGSnapshot`): adds the folder without waiting, then logs the first scan's
    /// progress twice and snapshots the window while the card shows.
    static func addFolderWatchingProgress(_ folder: URL, library: LibraryModel, window: NSWindow?, snapshot: URL?) async {
        Task { await library.addFolders([folder]) }
        try? await Task.sleep(for: .milliseconds(1500))
        log("adding: \(library.indexer.adding.values.map { "\($0.files) files, \($0.folders) folders" })")
        if let snapshot, let window {
            DeveloperHooks.snapshot(window, to: snapshot)
        }
        try? await Task.sleep(for: .milliseconds(1000))
        log("adding: \(library.indexer.adding.values.map { "\($0.files) files, \($0.folders) folders" })")
    }

    /// `-JGNewFolderCheck <name>`: makes an empty folder in the root shown (no dialog) and logs whether the sidebar
    /// tree shows it.
    static func newFolder(named name: String, library: LibraryModel) async {
        try? await Task.sleep(for: .milliseconds(800))
        guard let root = library.roots.first, let tree = library.trees[root.id], let parent = library.url(of: tree.folder) else { return }
        library.createdFolders.insert(parent.appendingPathComponent(name).path)
        library.onCreateFolder?(parent, name)
        try? await Task.sleep(for: .seconds(3))
        let shown = library.trees[root.id]?.children?.map(\.folder.name) ?? []
        log("sidebar children: \(shown)")
    }

    /// `-JGMiniPlayerCheck <snapshot.png>`: songs in the mini player, then the full player on a song (the mini player
    /// pauses), then that player closed (it resumes); logged, the bar snapshotted.
    static func miniPlayer(_ appModel: AppModel, library: LibraryModel, snapshot: URL) async {
        try? await Task.sleep(for: .milliseconds(600))
        let songs = library.refs.filter { $0.kind == .audio }.map(\.id)
        guard songs.count >= 2, let window = DeveloperHooks.mainWindow else {
            log("need two songs")
            return
        }
        await appModel.playInMiniPlayer([songs[0]])
        try? await Task.sleep(for: .milliseconds(800))
        log("mini playing: \(appModel.windowPlayer.playback.isPlaying)")
        DeveloperHooks.snapshot(window, to: snapshot)
        await appModel.openViewer(assetID: songs[1])
        try? await Task.sleep(for: .milliseconds(800))
        log("viewer playing: \(appModel.playback.isPlaying), mini playing: \(appModel.windowPlayer.playback.isPlaying)")
        appModel.closeViewer()
        try? await Task.sleep(for: .milliseconds(800))
        log("after closing the viewer, mini playing: \(appModel.windowPlayer.playback.isPlaying)")
        // ⌥‹ Library: the viewer's song goes on in the mini player where it was.
        await appModel.openViewer(assetID: songs[1])
        try? await Task.sleep(for: .milliseconds(1500))
        let viewerSeconds = appModel.mediaViewer?.playback.mediaSeconds ?? 0
        let handed = appModel.continueInMiniPlayer()
        try? await Task.sleep(for: .milliseconds(600))
        log(String(format: "handed off %@ at %.1f s: viewer %@, mini %@ at %.1f s, playing %@", "\(handed)", viewerSeconds,
                   appModel.viewer == nil ? "closed" : "open", appModel.windowPlayer.current?.name ?? "-",
                   appModel.windowPlayer.playback.mediaSeconds, "\(appModel.windowPlayer.playback.isPlaying)"))
        DeveloperHooks.snapshot(window, to: snapshot.deletingPathExtension().appendingPathExtension("handoff.png"))
        // The folder link with the song's kind filtered out: the filter turns on, the song is selected.
        library.toggleKind(.audio)
        try? await Task.sleep(for: .milliseconds(400))
        appModel.showInLibrary(songs[0])
        try? await Task.sleep(for: .milliseconds(800))
        log("reveal: audio shown \(library.state.kinds.contains(.audio)), selected \(library.selection.selected == [songs[0]])")
        // The smallest window: the bar keeps inside it (D-111).
        window.setContentSize(window.contentMinSize)
        try? await Task.sleep(for: .milliseconds(600))
        log("smallest window \(Int(window.frame.width)) × \(Int(window.frame.height))")
        DeveloperHooks.snapshot(window, to: snapshot.deletingPathExtension().appendingPathExtension("small.png"))
    }

    private static func find(_ view: NSView) -> GridCollectionView? {
        if let grid = view as? GridCollectionView {
            return grid
        }
        return view.subviews.lazy.compactMap(find).first
    }

    private static func log(_ line: String) {
        FileHandle.standardError.write(Data("reflow check: \(line)\n".utf8))
    }
}
