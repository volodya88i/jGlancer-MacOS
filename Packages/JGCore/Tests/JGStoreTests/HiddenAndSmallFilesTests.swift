import Foundation
import JGModel
import Testing
@testable import JGStore

/// Hidden subfolders and the small-file filter (WIN-061): views of the library, nothing leaves the index.
struct HiddenAndSmallFilesTests {
    /// /lib: top.jpg; Icons/a.png (1 KB), Icons/Deep/b.png; Icons2/c.jpg (not below Icons); Photos/d.jpg.
    private struct Library {
        let store: LibraryStore
        let rootID: Int64
        /// Folder ids by relative path.
        let folders: [String: Int64]
    }

    private func library() async throws -> Library {
        let store = try LibraryStore.inMemory()
        let root = try await store.addRoot(path: "/lib")
        try await store.scan(root.id, files: [file("top.jpg", size: 500_000, inode: 1)],
                             subdirectories: ["Icons", "Icons2", "Photos"])
        try await store.scan(root.id, "Icons", files: [file("a.png", size: 1000, inode: 2)], subdirectories: ["Deep"])
        try await store.scan(root.id, "Icons/Deep", files: [file("b.png", size: 2000, inode: 3)])
        try await store.scan(root.id, "Icons2", files: [file("c.jpg", size: 300_000, inode: 4)])
        try await store.scan(root.id, "Photos", files: [file("d.jpg", size: 400_000, inode: 5)])
        let folders = try await store.folders(rootID: root.id)
        return Library(store: store, rootID: root.id, folders: Dictionary(uniqueKeysWithValues: folders.map { ($0.relativePath, $0.id) }))
    }

    private func names(_ store: LibraryStore, _ query: AssetQuery) async throws -> [String] {
        let refs = try await store.assetRefs(for: query)
        return try await store.assets(ids: refs.map(\.id)).map(\.name).sorted()
    }

    @Test func aHiddenFolderAndEverythingBelowLeaveEveryScopeButAlbums() async throws {
        let library = try await library()
        let (store, rootID, folders) = (library.store, library.rootID, library.folders)
        let hidden: Set<Int64> = try [#require(folders["Icons"])]
        let top = try #require(folders[""])
        #expect(try await names(store, AssetQuery(scope: .folder(id: top, includeSubfolders: true), hiddenFolders: hidden))
            == ["c.jpg", "d.jpg", "top.jpg"])
        #expect(try await names(store, AssetQuery(scope: .root(id: rootID), hiddenFolders: hidden)) == ["c.jpg", "d.jpg", "top.jpg"])
        #expect(try await names(store, AssetQuery(search: "png", hiddenFolders: hidden)).isEmpty)
        #expect(try await store.totals(for: AssetQuery(hiddenFolders: hidden)).assets == 3)
        // Still indexed: shown again when no longer hidden, and an album keeps showing its files.
        #expect(try await names(store, AssetQuery()).count == 5)
        let ids = try await store.idsByName()
        let album = try await store.createAlbum(name: "Kept")
        try await store.addToAlbum(album.id, assetIDs: [#require(ids["b.png"])])
        #expect(try await names(store, AssetQuery(scope: .album(id: album.id), hiddenFolders: hidden)) == ["b.png"])
    }

    @Test func smallFilesLeaveEveryViewAlbumsIncluded() async throws {
        let store = try await library().store
        #expect(try await names(store, AssetQuery(minSize: 10 * 1024)) == ["c.jpg", "d.jpg", "top.jpg"])
        #expect(try await store.totals(for: AssetQuery(minSize: 10 * 1024)).assets == 3)
        let ids = try await store.idsByName()
        let album = try await store.createAlbum(name: "Icons")
        try await store.addToAlbum(album.id, assetIDs: [#require(ids["a.png"]), #require(ids["d.jpg"])])
        #expect(try await names(store, AssetQuery(scope: .album(id: album.id), minSize: 10 * 1024)) == ["d.jpg"])
    }

    @Test func theSizeMapGetsTheQuerysFilesWithTheirFolders() async throws {
        let library = try await library()
        let top = try #require(library.folders[""])
        let entries = try await library.store.sizeEntries(
            for: AssetQuery(scope: .folder(id: top, includeSubfolders: true), hiddenFolders: [#require(library.folders["Icons"])])
        )
        #expect(entries.map(\.name).sorted() == ["c.jpg", "d.jpg", "top.jpg"])
        #expect(entries.first { $0.name == "d.jpg" }?.folderID == library.folders["Photos"])
        #expect(entries.first { $0.name == "d.jpg" }?.size == 400_000)
    }
}
