import Foundation
import JGModel
import Testing
@testable import JGStore

/// Asset ids by file name; an unknown name gives an id no asset has.
struct Names {
    let ids: [String: Int64]

    subscript(name: String) -> Int64 {
        ids[name] ?? -1
    }
}

struct AlbumTests {
    func library() async throws -> (LibraryStore, Names) {
        let store = try LibraryStore.inMemory()
        let root = try await store.addRoot(path: "/lib")
        try await store.scan(root.id, files: [
            file("a.jpg"), file("b.jpg", size: 200), file("c.mov", size: 300, kind: .video), file("d.mp3", size: 400, kind: .audio),
        ])
        return try await (store, Names(ids: store.idsByName()))
    }

    func refs(_ store: LibraryStore, _ album: Int64, kinds: Set<MediaKind> = Set(MediaKind.allCases)) async throws -> [Int64] {
        try await store.assetRefs(for: AssetQuery(scope: .album(id: album), kinds: kinds)).map(\.id)
    }

    @Test func itemsKeepTheirOrderSkipDuplicatesAndFollowTheKindFilter() async throws {
        let (store, ids) = try await library()
        let album = try await store.createAlbum(name: "Trip")
        let added = try await store.addToAlbum(
            album.id,
            assetIDs: [ids["c.mov"], ids["a.jpg"], ids["c.mov"]]
        )
        #expect(added == [ids["c.mov"], ids["a.jpg"]])
        #expect(try await store
            .addToAlbum(album.id, assetIDs: [ids["a.jpg"], ids["b.jpg"]]) == [ids["b.jpg"]])
        #expect(try await refs(store, album.id) == [ids["c.mov"], ids["a.jpg"], ids["b.jpg"]])
        #expect(try await refs(store, album.id, kinds: [.photo]) == [ids["a.jpg"], ids["b.jpg"]])
        let totals = try await store.totals(for: AssetQuery(scope: .album(id: album.id)))
        #expect(totals.assets == 3)
        #expect(totals.bytes == 600)
        let listed = try await store.albums()
        #expect(listed.map(\.itemCount) == [3])
        #expect(listed.first?.coverAssetID == ids["c.mov"])
    }

    @Test func membershipSurvivesMovesRenamesAndATrashRoundTrip() async throws {
        let (store, ids) = try await library()
        let album = try await store.createAlbum(name: "Keep")
        try await store.addToAlbum(album.id, assetIDs: [ids["a.jpg"], ids["b.jpg"]])
        try await store.moveAsset(from: "/lib/a.jpg", to: "/lib/sub/renamed.jpg")
        #expect(try await refs(store, album.id) == [ids["a.jpg"], ids["b.jpg"]])
        try await store.markMissing(at: "/lib/b.jpg")
        // A vanished file stays as a placeholder in its albums, not in folders, and is not counted.
        #expect(try await refs(store, album.id) == [ids["a.jpg"], ids["b.jpg"]])
        #expect(try await store.albums().first?.itemCount == 1)
        try await store.revive(at: "/lib/b.jpg")
        #expect(try await store.albums().first?.itemCount == 2)
    }

    @Test func oldPlaceholdersArePurgedAfterThirtyDays() async throws {
        let (store, ids) = try await library()
        let album = try await store.createAlbum(name: "Old")
        try await store.addToAlbum(album.id, assetIDs: [ids["a.jpg"], ids["b.jpg"]])
        let then = Date(timeIntervalSince1970: 1_800_000_000)
        try await store.markMissing(at: "/lib/a.jpg", now: then)
        #expect(try await store.purgeAlbumPlaceholders(now: then.addingTimeInterval(29 * 24 * 3600)) == 0)
        #expect(try await store.purgeAlbumPlaceholders(now: then.addingTimeInterval(31 * 24 * 3600)) == 1)
        #expect(try await refs(store, album.id) == [ids["b.jpg"]])
    }

    @Test func removeAndRestoreReorderCoverAndDelete() async throws {
        let (store, ids) = try await library()
        let album = try await store.createAlbum(name: "Order")
        let all = [ids["a.jpg"], ids["b.jpg"], ids["c.mov"], ids["d.mp3"]]
        try await store.addToAlbum(album.id, assetIDs: all)
        let removed = try await store.removeFromAlbum(album.id, assetIDs: [ids["b.jpg"], ids["d.mp3"]])
        #expect(try await refs(store, album.id) == [ids["a.jpg"], ids["c.mov"]])
        try await store.restoreToAlbum(album.id, items: removed)
        #expect(try await refs(store, album.id) == all)
        try await store.moveInAlbum(
            album.id,
            assetIDs: [ids["d.mp3"], ids["c.mov"]],
            before: ids["a.jpg"]
        )
        #expect(try await refs(store, album.id) == [
            ids["c.mov"],
            ids["d.mp3"],
            ids["a.jpg"],
            ids["b.jpg"],
        ])
        try await store.moveInAlbum(album.id, assetIDs: [ids["c.mov"]], before: nil)
        #expect(try await refs(store, album.id).last == ids["c.mov"])
        try await store.setAlbumCover(album.id, assetID: ids["b.jpg"])
        #expect(try await store.albums().first?.coverAssetID == ids["b.jpg"])
        try await store.renameAlbum(album.id, to: "Renamed")
        #expect(try await store.albums().map(\.name) == ["Renamed"])
        try await store.deleteAlbum(album.id)
        #expect(try await store.albums().isEmpty)
        #expect(try await store.idsByName().count == 4)
    }

    @Test func aReplacedFilesRowLeavesItsAlbums() async throws {
        let (store, ids) = try await library()
        let album = try await store.createAlbum(name: "Replace")
        try await store.addToAlbum(album.id, assetIDs: [ids["a.jpg"], ids["b.jpg"]])
        // Move b over a (a was trashed first, as Replace does): a's tombstone row is deleted with its items.
        try await store.markMissing(at: "/lib/a.jpg")
        try await store.moveAsset(from: "/lib/b.jpg", to: "/lib/a.jpg")
        #expect(try await refs(store, album.id) == [ids["b.jpg"]])
    }
}
