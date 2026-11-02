import Foundation
import JGModel
import Testing
@testable import JGStore

struct QueryTests {
    /// /lib: IMG_10.jpg (photo, 3 KB), IMG_2.jpg (photo, 1 KB), clip.mov (video, 2 KB), song.m4a (audio);
    /// /lib/sub: IMG_1.jpg; /lib/sub/deep: z.jpg.
    private func library() async throws -> (LibraryStore, RootFolder) {
        let store = try LibraryStore.inMemory()
        let root = try await store.addRoot(path: "/lib")
        try await store.scan(root.id, files: [
            file("IMG_10.jpg", size: 3000, modified: 30, inode: 1),
            file("IMG_2.jpg", size: 1000, modified: 10, inode: 2),
            file("clip.mov", size: 2000, modified: 20, inode: 3, kind: .video),
            file("song.m4a", size: 500, modified: 40, inode: 4, kind: .audio),
        ], subdirectories: ["sub"])
        try await store.scan(root.id, "sub", files: [file("IMG_1.jpg", inode: 5)], subdirectories: ["deep"])
        try await store.scan(root.id, "sub/deep", files: [file("z.jpg", inode: 6)])
        return (store, root)
    }

    private func names(_ store: LibraryStore, _ query: AssetQuery) async throws -> [String] {
        let refs = try await store.assetRefs(for: query)
        return try await store.assets(ids: refs.map(\.id)).map(\.name)
    }

    @Test func sortsAndDirections() async throws {
        let (store, root) = try await library()
        let top = try #require(try await store.folders(rootID: root.id).first { $0.relativePath.isEmpty })
        let scope = AssetQuery.Scope.folder(id: top.id, includeSubfolders: false)
        #expect(try await names(store, AssetQuery(scope: scope, sort: .name)) == ["clip.mov", "IMG_2.jpg", "IMG_10.jpg", "song.m4a"])
        #expect(try await names(store, AssetQuery(scope: scope, sort: .size, ascending: false)) == [
            "IMG_10.jpg",
            "clip.mov",
            "IMG_2.jpg",
            "song.m4a",
        ])
        #expect(try await names(store, AssetQuery(scope: scope, sort: .dateModified)) == [
            "IMG_2.jpg",
            "clip.mov",
            "IMG_10.jpg",
            "song.m4a",
        ])
        #expect(try await names(store, AssetQuery(scope: scope, sort: .kind)) == ["IMG_2.jpg", "IMG_10.jpg", "clip.mov", "song.m4a"])
    }

    @Test func capturedDateFallsBackToModificationDate() async throws {
        let (store, root) = try await library()
        let top = try #require(try await store.folders(rootID: root.id).first { $0.relativePath.isEmpty })
        let ids = try await store.idsByName()
        let song = try #require(ids["song.m4a"])
        // The song was "captured" before everything else.
        try await store.saveMetadata([MetadataUpdate(
            id: song,
            modifiedAt: base.addingTimeInterval(40),
            state: .extracted,
            capturedAt: base
        )])
        let scope = AssetQuery.Scope.folder(id: top.id, includeSubfolders: false)
        #expect(try await names(store, AssetQuery(scope: scope, sort: .dateCaptured)) == [
            "song.m4a",
            "IMG_2.jpg",
            "clip.mov",
            "IMG_10.jpg",
        ])
    }

    @Test func kindFilterAndScopes() async throws {
        let (store, root) = try await library()
        let folders = try await store.folders(rootID: root.id)
        let sub = try #require(folders.first { $0.relativePath == "sub" })
        #expect(try await store.assetRefs(for: AssetQuery(scope: .library)).count == 6)
        #expect(try await store.assetRefs(for: AssetQuery(scope: .root(id: root.id), kinds: [.photo])).count == 4)
        #expect(try await store.assetRefs(for: AssetQuery(kinds: [.video, .audio])).map(\.kind).sorted { $0.rawValue < $1.rawValue } == [
            .video,
            .audio,
        ])
        #expect(try await store.assetRefs(for: AssetQuery(kinds: [])).isEmpty)
        #expect(try await names(store, AssetQuery(scope: .folder(id: sub.id, includeSubfolders: false))) == ["IMG_1.jpg"])
        #expect(try await names(store, AssetQuery(scope: .folder(id: sub.id, includeSubfolders: true))) == ["IMG_1.jpg", "z.jpg"])
    }

    @Test func subfolderRangeDoesNotLeakIntoSiblingsWithTheSamePrefix() async throws {
        let store = try LibraryStore.inMemory()
        let root = try await store.addRoot(path: "/lib")
        try await store.scan(root.id, files: [], subdirectories: ["a", "a b", "ab"])
        try await store.scan(root.id, "a", files: [file("1.jpg", inode: 1)])
        try await store.scan(root.id, "a b", files: [file("2.jpg", inode: 2)])
        try await store.scan(root.id, "ab", files: [file("3.jpg", inode: 3)])
        let folderA = try #require(try await store.folders(rootID: root.id).first { $0.relativePath == "a" })
        #expect(try await names(store, AssetQuery(scope: .folder(id: folderA.id, includeSubfolders: true))) == ["1.jpg"])
    }

    @Test func tombstonesAreHiddenFromQueries() async throws {
        let (store, root) = try await library()
        try await store.scan(root.id, files: [file("IMG_2.jpg", size: 1000, modified: 10, inode: 2)], subdirectories: ["sub"])
        #expect(try await store.assetRefs(for: AssetQuery(scope: .root(id: root.id))).count == 3)
    }

    @Test func fullRowsComeBackInRequestedOrderWithPaths() async throws {
        let (store, _) = try await library()
        let ids = try await store.idsByName()
        let order = try [#require(ids["z.jpg"]), #require(ids["clip.mov"])]
        #expect(try await store.assets(ids: order + [999]).map(\.name) == ["z.jpg", "clip.mov"])
        #expect(try await store.fileURL(assetID: order[0])?.path == "/lib/sub/deep/z.jpg")
    }

    @Test func assetsCarryTheirFileURLAndTotalsAddUp() async throws {
        let (store, root) = try await library()
        let ids = try await store.idsByName()
        let deepID = try #require(ids["z.jpg"])
        let deep = try #require(try await store.assets(ids: [deepID]).first)
        #expect(deep.url.path == "/lib/sub/deep/z.jpg")
        let photos = try await store.totals(for: AssetQuery(scope: .root(id: root.id), kinds: [.photo]))
        #expect(photos.assets == 4)
        #expect(photos.bytes == 3000 + 1000 + 100 + 100)
        #expect(try await store.totals(for: AssetQuery(kinds: [])).assets == 0)
        let selected = try [#require(ids["clip.mov"]), #require(ids["song.m4a"])]
        #expect(try await store.totalSize(ids: selected) == 2500)
    }

    @Test func pendingMetadataIsSavedOnlyWhileTheFileIsUnchanged() async throws {
        let (store, _) = try await library()
        let pending = try await store.pendingMetadata(limit: 100)
        #expect(pending.count == 6)
        let first = try #require(pending.first)
        let stale = MetadataUpdate(id: first.id, modifiedAt: base.addingTimeInterval(9999), state: .extracted, width: 1)
        try await store.saveMetadata([stale])
        #expect(try await store.statistics().pendingMetadata == 6)
        try await store.saveMetadata([MetadataUpdate(id: first.id, modifiedAt: first.modifiedAt, state: .extracted, width: 1)])
        #expect(try await store.statistics().pendingMetadata == 5)
        #expect(try await store.pendingMetadata(afterID: first.id, limit: 100).count == 5)
    }

    @Test func observationEmitsInitialValueAndChanges() async throws {
        let store = try LibraryStore.inMemory()
        let root = try await store.addRoot(path: "/lib")
        var iterator = store.observeAssetRefs(AssetQuery()).makeAsyncIterator()
        #expect(try await iterator.next()?.isEmpty == true)
        try await store.scan(root.id, files: [file("a.jpg", inode: 1)])
        #expect(try await iterator.next()?.count == 1)
    }
}

struct LocateTests {
    @Test func pathsResolveToRootFolderAndAsset() async throws {
        let store = try LibraryStore.inMemory()
        let root = try await store.addRoot(path: "/lib")
        try await store.scan(root.id, files: [file("a.jpg", inode: 1)], subdirectories: ["sub"])
        try await store.scan(root.id, "sub", files: [file("b.jpg", inode: 2)])
        let ids = try await store.idsByName()
        let file = try #require(try await store.location(of: "/lib/sub/b.jpg", isDirectory: false))
        #expect(file.rootID == root.id)
        #expect(file.assetID == ids["b.jpg"])
        let folder = try #require(try await store.location(of: "/lib/sub", isDirectory: true))
        #expect(folder.folderID != nil && folder.assetID == nil)
        let top = try #require(try await store.location(of: "/lib", isDirectory: true))
        #expect(top.folderID != nil)
        let unknown = try #require(try await store.location(of: "/lib/sub/new.jpg", isDirectory: false))
        #expect(unknown.assetID == nil && unknown.folderID == folder.folderID)
        #expect(try await store.location(of: "/library/a.jpg", isDirectory: false) == nil)
        #expect(try await store.location(of: "/elsewhere/a.jpg", isDirectory: false) == nil)
    }
}
