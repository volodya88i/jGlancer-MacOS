import Foundation
import GRDB
import Testing
@testable import JGStore

struct MigrationAndRootTests {
    @Test func migrationsCreateTheSchemaOnceAndReopenCleanly() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("JGStoreTests-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("library.sqlite")
        let first = try LibraryStore.open(at: url)
        #expect(try await first.appliedMigrations() == [
            "v1-library",
            "v2-albums",
            "v3-search",
            "v4-audio-analysis",
            "v5-no-typescript",
            "v6-cloud-only",
            "v7-root-icons",
        ])
        let tables = try await first.writer.read { db in
            try String.fetchAll(db, sql: "SELECT name FROM sqlite_master WHERE type = 'table' ORDER BY name")
        }
        #expect(Set(tables).isSuperset(of: ["root_folder", "folder", "asset"]))
        let second = try LibraryStore.open(at: url)
        #expect(try await second.appliedMigrations() == [
            "v1-library",
            "v2-albums",
            "v3-search",
            "v4-audio-analysis",
            "v5-no-typescript",
            "v6-cloud-only",
            "v7-root-icons",
        ])
        let mode = try await second.writer.read { db in try String.fetchOne(db, sql: "PRAGMA journal_mode") }
        #expect(mode == "wal")
    }

    @Test func rootsRejectDuplicatesAndOverlaps() async throws {
        let store = try LibraryStore.inMemory()
        let root = try await store.addRoot(path: "/Volumes/Media/Photos/")
        #expect(root.path == "/Volumes/Media/Photos")
        await #expect(throws: StoreError.rootAlreadyExists(path: "/Volumes/Media/Photos")) {
            try await store.addRoot(path: "/Volumes/Media/Photos")
        }
        await #expect(throws: StoreError.rootOverlapsExisting(path: "/Volumes/Media/Photos/2024", existing: "/Volumes/Media/Photos")) {
            try await store.addRoot(path: "/Volumes/Media/Photos/2024")
        }
        await #expect(throws: StoreError.rootOverlapsExisting(path: "/Volumes/Media", existing: "/Volumes/Media/Photos")) {
            try await store.addRoot(path: "/Volumes/Media")
        }
        _ = try await store.addRoot(path: "/Volumes/Media/Photos 2")
        #expect(try await store.roots().count == 2)
    }

    @Test func removingARootRemovesItsRowsOnly() async throws {
        let store = try LibraryStore.inMemory()
        let first = try await store.addRoot(path: "/a")
        let second = try await store.addRoot(path: "/b")
        try await store.scan(first.id, files: [file("1.jpg")])
        try await store.scan(second.id, files: [file("2.jpg")])
        try await store.removeRoot(id: first.id)
        #expect(try await store.idsByName().keys.sorted() == ["2.jpg"])
        #expect(try await store.folders(rootID: first.id).isEmpty)
    }

    @Test func rootIconsAreSetReplacedClearedAndGoWithTheirRoot() async throws {
        let store = try LibraryStore.inMemory()
        let first = try await store.addRoot(path: "/a")
        let second = try await store.addRoot(path: "/b")
        try await store.setRootIcon(.symbol("music.note"), for: first.id)
        try await store.setRootIcon(.picture(Data([1, 2, 3])), for: second.id)
        #expect(try await store.rootIcons() == [first.id: .symbol("music.note"), second.id: .picture(Data([1, 2, 3]))])
        try await store.setRootIcon(.emoji("🎸"), for: first.id)
        #expect(try await store.rootIcons()[first.id] == .emoji("🎸"))
        try await store.setRootIcon(nil, for: first.id)
        #expect(try await store.rootIcons()[first.id] == nil)
        try await store.removeRoot(id: second.id)
        #expect(try await store.rootIcons().isEmpty)
    }

    @Test func eventStateIsPersisted() async throws {
        let store = try LibraryStore.inMemory()
        let root = try await store.addRoot(path: "/a")
        #expect(root.lastEventID == nil)
        try await store.updateEventState(rootID: root.id, lastEventID: UInt64.max - 5, eventDatabaseUUID: "UUID")
        let reloaded = try await store.root(id: root.id)
        #expect(reloaded.lastEventID == UInt64.max - 5)
        #expect(reloaded.eventDatabaseUUID == "UUID")
    }
}
