import Foundation
import JGModel
import Testing
@testable import JGStore

struct FileOpsStoreTests {
    @Test func moveKeepsTheIdAndCreatesFolders() async throws {
        let store = try LibraryStore.inMemory()
        let root = try await store.addRoot(path: "/lib")
        try await store.scan(root.id, files: [file("a.jpg")])
        let id = try #require(try await store.idsByName()["a.jpg"])
        let moved = try await store.moveAsset(from: "/lib/a.jpg", to: "/lib/new/deeper/b.jpg")
        #expect(moved == id)
        #expect(try await store.idsByName() == ["b.jpg": id])
        let location = try await store.location(of: "/lib/new/deeper/b.jpg", isDirectory: false)
        #expect(location?.assetID == id)
    }

    @Test func movingOutOfTheLibraryLeavesATombstoneThatRevives() async throws {
        let store = try LibraryStore.inMemory()
        let root = try await store.addRoot(path: "/lib")
        try await store.scan(root.id, files: [file("a.jpg")])
        let id = try #require(try await store.idsByName()["a.jpg"])
        try await store.moveAsset(from: "/lib/a.jpg", to: "/elsewhere/a.jpg")
        #expect(try await store.idsByName().isEmpty)
        // Trash and restore at the original path.
        let other = try await store.moveAsset(from: "/lib/missing.jpg", to: "/lib/x.jpg")
        #expect(other == nil)
        #expect(try await store.revive(at: "/lib/a.jpg") == id)
        #expect(try await store.idsByName() == ["a.jpg": id])
        try await store.markMissing(at: "/lib/a.jpg")
        #expect(try await store.idsByName().isEmpty)
        #expect(try await store.revive(at: "/lib/a.jpg") == id)
    }

    @Test func aReplacedFilesTombstoneMakesRoom() async throws {
        let store = try LibraryStore.inMemory()
        let root = try await store.addRoot(path: "/lib")
        try await store.scan(root.id, files: [file("a.jpg"), file("b.jpg", size: 200)])
        let ids = try await store.idsByName()
        try await store.markMissing(at: "/lib/b.jpg")
        try await store.moveAsset(from: "/lib/a.jpg", to: "/lib/b.jpg")
        #expect(try await store.idsByName() == ["b.jpg": ids["a.jpg"]])
    }
}
