import Foundation
import JGModel
import Testing
@testable import JGStore

struct FlagAndSearchTests {
    /// /lib: IMG_1234 Отпуск.jpg, IMG_99.jpg, 50%_off.png, clip.mov.
    private func library() async throws -> LibraryStore {
        let store = try LibraryStore.inMemory()
        let root = try await store.addRoot(path: "/lib")
        try await store.scan(root.id, files: [
            file("IMG_1234 Отпуск.jpg", inode: 1), file("IMG_99.jpg", inode: 2), file("50%_off.png", inode: 3),
            file("clip.mov", inode: 4, kind: .video),
        ])
        return store
    }

    private func names(_ store: LibraryStore, _ query: AssetQuery) async throws -> [String] {
        let refs = try await store.assetRefs(for: query)
        return try await store.assets(ids: refs.map(\.id)).map(\.name).sorted()
    }

    @Test func flagsAreSetFilteredAndRestored() async throws {
        let store = try await library()
        let ids = try await store.idsByName()
        let photos = try [#require(ids["IMG_99.jpg"]), #require(ids["clip.mov"])]
        let previous = try await store.setFlag(.red, assetIDs: photos)
        #expect(previous.values.allSatisfy { $0 == .none })
        try await store.setFlag(.accent, assetIDs: [#require(ids["50%_off.png"])])
        #expect(try await names(store, AssetQuery(flagFilter: .flagged)) == ["50%_off.png", "IMG_99.jpg", "clip.mov"])
        #expect(try await names(store, AssetQuery(flagFilter: .only(.red))) == ["IMG_99.jpg", "clip.mov"])
        #expect(try await store.assets(ids: [photos[0]]).first?.flag == .red)
        try await store.restoreFlags(previous)
        #expect(try await names(store, AssetQuery(flagFilter: .only(.red))).isEmpty)
    }

    @Test func pressingAFlagTogglesForTheWholeSelection() {
        #expect(AssetFlag.applying(.red, to: [.none, .red]) == .red)
        #expect(AssetFlag.applying(.red, to: [.red, .red]) == .none)
        #expect(AssetFlag.applying(.accent, to: [.red]) == .accent)
        #expect(AssetFlag.applying(.none, to: [.red]) == .none)
    }

    @Test func searchFindsSubstringsInAnyCaseAndFollowsRenames() async throws {
        let store = try await library()
        #expect(try await names(store, AssetQuery(search: "отпуск")) == ["IMG_1234 Отпуск.jpg"])
        #expect(try await names(store, AssetQuery(search: "G_12")) == ["IMG_1234 Отпуск.jpg"])
        #expect(try await names(store, AssetQuery(search: "img")) == ["IMG_1234 Отпуск.jpg", "IMG_99.jpg"])
        // Short text uses LIKE, with % and _ taken literally.
        #expect(try await names(store, AssetQuery(search: "%_")) == ["50%_off.png"])
        #expect(try await names(store, AssetQuery(search: "99")) == ["IMG_99.jpg"])
        #expect(try await names(store, AssetQuery(search: "  ")).count == 4)
        // Quotes in the text do not break the query.
        #expect(try await names(store, AssetQuery(search: "a\"b")).isEmpty)
        _ = try await store.moveAsset(from: "/lib/clip.mov", to: "/lib/Holiday clip.mov")
        #expect(try await names(store, AssetQuery(search: "holiday")) == ["Holiday clip.mov"])
        #expect(try await names(store, AssetQuery(flagFilter: .flagged, search: "clip")).isEmpty)
    }

    @Test func albumsApplyFlagsAndSearch() async throws {
        let store = try await library()
        let ids = try await store.idsByName()
        let album = try await store.createAlbum(name: "A")
        try await store.addToAlbum(album.id, assetIDs: Array(ids.values))
        try await store.setFlag(.blue, assetIDs: [#require(ids["IMG_99.jpg"])])
        #expect(try await names(store, AssetQuery(scope: .album(id: album.id), flagFilter: .flagged)) == ["IMG_99.jpg"])
        #expect(try await names(store, AssetQuery(scope: .album(id: album.id), search: "отп")) == ["IMG_1234 Отпуск.jpg"])
    }
}
