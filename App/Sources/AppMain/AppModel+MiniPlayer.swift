import AppKit
import JGModel
import JGPlayback

/// The window's mini player (D-88): one song plays through the songs the grid shows, several play in their order.
extension AppModel {
    func playInMiniPlayer(_ ids: [Int64]) async {
        guard let library = activeLibrary, !ids.isEmpty else { return }
        let queueIDs = ids.count == 1 ? library.refs.filter { $0.kind == .audio }.map(\.id) : ids
        let assets = await (try? library.store.assets(ids: queueIDs)) ?? []
        let items = assets.filter { $0.kind == .audio }.map(PlaybackItem.init(asset:))
        let start = items.firstIndex { $0.assetID == ids[0] } ?? 0
        let folder = assets.first { $0.id == ids[0] }.flatMap { library.folder(id: $0.folderID)?.name }
        windowPlayer.play(items, from: start, thumbnails: library.thumbnails, folderName: folder)
    }

    /// A file in its folder, selected and in view, even if the kind filter hid its kind (the bar's folder link, a copy
    /// in Find Duplicates; W-100).
    func showInLibrary(_ assetID: Int64) {
        guard let library = activeLibrary else { return }
        if viewer != nil {
            closeViewer()
        }
        Task {
            guard let asset = try? await library.store.assets(ids: [assetID]).first else { return }
            library.select(folderID: asset.folderID)
            if !library.state.kinds.contains(asset.kind) {
                library.toggleKind(asset.kind)
            }
            // The folder's files arrive a moment later.
            for _ in 0 ..< 40 where !library.isLoaded || library.order.index(of: assetID) == nil {
                try? await Task.sleep(for: .milliseconds(50))
            }
            library.reveal(assetID)
        }
    }

    /// "‹ Library" in the video and audio viewer; with ⌥ a song goes on in the mini player.
    func leaveMediaViewer() {
        if NSEvent.modifierFlags.contains(.option), continueInMiniPlayer() {
            return
        }
        closeViewer()
    }

    /// The song of the audio viewer goes on in the mini player from where it is, with the viewer's songs as its
    /// queue; the viewer closes. False when the viewer shows no song.
    @discardableResult
    func continueInMiniPlayer() -> Bool {
        guard let viewer = mediaViewer, let current = viewer.playback.queue.current, current.kind == .audio,
              let library = activeLibrary
        else { return false }
        let queue = viewer.playback.queue
        let songs = queue.items.filter { $0.kind == .audio }
        let index = songs.firstIndex { $0.id == current.id } ?? 0
        let seconds = viewer.playback.mediaSeconds
        closeViewer()
        // The folder link names the folder the grid shows, when the song is in it.
        let isShown = current.assetID.map { library.order.index(of: $0) != nil } ?? false
        let folder = isShown ? library.state.folderID.flatMap { library.folder(id: $0)?.name } : nil
        windowPlayer.play(songs, from: index, at: seconds, thumbnails: library.thumbnails, folderName: folder)
        return true
    }
}
