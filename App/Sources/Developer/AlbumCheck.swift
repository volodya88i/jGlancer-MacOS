import AppKit
import JGModel

/// End-to-end check of PLAN Phase 8 on test copies: an album from every photo, a member moved by the app stays,
/// Remove from Album and its undo, then the album stays open for a snapshot.
@MainActor
enum AlbumCheck {
    static func run(appModel: AppModel, library: LibraryModel, moveInto folder: URL) async {
        guard let fileOps = appModel.fileOps else { return }
        let photos = await (try? library.store.assetRefs(for: AssetQuery(kinds: [.photo]))) ?? []
        let ids = photos.map(\.id)
        guard let albumID = await library.createAlbum(name: "Check", with: ids) else { return }
        try? await Task.sleep(for: .milliseconds(300))
        library.select(albumID: albumID)
        try? await Task.sleep(for: .milliseconds(300))
        log("album items: \(library.refs.count) of \(ids.count) photos; sidebar albums: \(library.albums.map(\.name))")
        if let first = ids.first, let url = try? await library.store.fileURL(assetID: first) {
            fileOps.transfer([url], to: folder, copying: false)
            await waitUntilIdle(fileOps)
            let order = await (try? library.store.albumOrder(albumID)) ?? []
            log("after moving \(url.lastPathComponent) into \(folder.lastPathComponent): still in album \(order.contains(first))")
        }
        await library.removeFromCurrentAlbum(Array(ids.prefix(2)))
        try? await Task.sleep(for: .milliseconds(300))
        log("after Remove from Album: \(library.refs.count) items, undo: \(fileOps.undoTitle)")
        fileOps.undo()
        try? await Task.sleep(for: .milliseconds(500))
        let order = await (try? library.store.albumOrder(albumID)) ?? []
        log("after undo: \(library.refs.count) items, order kept: \(order == ids)")
    }

    private static func waitUntilIdle(_ fileOps: FileOperationsModel) async {
        try? await Task.sleep(for: .milliseconds(100))
        while fileOps.isRunning {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private static func log(_ line: String) {
        FileHandle.standardError.write(Data("album check: \(line)\n".utf8))
    }
}
