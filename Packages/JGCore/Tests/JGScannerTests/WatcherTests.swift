import Foundation
import JGModel
import JGStore
import JGTestSupport
import Testing
@testable import JGScanner

struct ChangePlannerTests {
    private func event(_ path: String, _ flags: FileSystemEventFlags) -> FileSystemEvent {
        FileSystemEvent(path: path, flags: flags, id: 1)
    }

    @Test func fileEventsRescanTheirFolderShallowly() {
        let plan = ChangePlanner.plan([
            event("/lib/2024/a.jpg", [.itemCreated, .itemIsFile]),
            event("/lib/2024/b.jpg", [.itemModified, .itemIsFile]),
            event("/lib/c.jpg", [.itemRemoved, .itemIsFile]),
        ], rootPath: "/lib")
        #expect(plan == [RescanTarget(relativePath: "", recursive: false), RescanTarget(relativePath: "2024", recursive: false)])
    }

    @Test func directoryEventsRescanTheDirectoryDeeplyAndCoalesce() {
        let plan = ChangePlanner.plan([
            event("/lib/2024", [.itemRenamed, .itemIsDirectory]),
            event("/lib/2024/May/x.jpg", [.itemCreated, .itemIsFile]),
        ], rootPath: "/lib")
        #expect(plan == [RescanTarget(relativePath: "", recursive: false), RescanTarget(relativePath: "2024", recursive: true)])
    }

    @Test func droppedEventsForceAFullRescanAndHiddenOrForeignPathsAreIgnored() {
        #expect(ChangePlanner.plan([event("/lib/a.jpg", [.kernelDropped])], rootPath: "/lib")
            == [RescanTarget(relativePath: "", recursive: true)])
        #expect(ChangePlanner.plan([
            event("/lib/.cache/a.jpg", [.itemCreated]),
            event("/library-other/a.jpg", [.itemCreated]),
            event("", [.historyDone]),
        ], rootPath: "/lib").isEmpty)
        #expect(ChangePlanner.plan([event("/lib/x", [.mustScanSubDirs])], rootPath: "/lib")
            == [RescanTarget(relativePath: "x", recursive: true)])
    }
}

/// Live FSEvents tests on temporary folders; generous timeouts because delivery is asynchronous.
struct FolderWatcherTests {
    @Test func liveEventsAreDelivered() async throws {
        let folder = try TemporaryDirectory()
        let stream = FolderWatcher(latency: 0.1).events(at: folder.url.path)
        let received = Task {
            for await batch in stream where batch.contains(where: { $0.path.hasSuffix("new.jpg") }) {
                return true
            }
            return false
        }
        try await Task.sleep(for: .milliseconds(500))
        try folder.write("new.jpg")
        let watchdog = Task {
            try await Task.sleep(for: .seconds(10))
            received.cancel()
        }
        #expect(await received.value)
        watchdog.cancel()
    }

    @Test func historyIsReplayedFromAStoredEventID() async throws {
        let folder = try TemporaryDirectory()
        let since = FolderWatcher.currentEventID()
        try folder.write("while-closed.jpg")
        try await Task.sleep(for: .seconds(1))
        let stream = FolderWatcher(latency: 0.1).events(at: folder.url.path, since: since)
        let received = Task {
            var sawFile = false
            for await batch in stream {
                sawFile = sawFile || batch.contains { $0.path.hasSuffix("while-closed.jpg") }
                if batch.contains(where: { $0.flags.contains(.historyDone) }) {
                    return sawFile
                }
            }
            return sawFile
        }
        let watchdog = Task {
            try await Task.sleep(for: .seconds(10))
            received.cancel()
        }
        #expect(await received.value)
        watchdog.cancel()
        #expect(FolderWatcher.eventDatabaseUUID(forPath: folder.url.path) != nil)
    }

    @Test func watchingKeepsTheLibraryInSync() async throws {
        let folder = try TemporaryDirectory()
        try folder.write("a.jpg")
        let scanner = try LibraryScanner(store: LibraryStore.inMemory())
        let (root, _) = try await scanner.addRoot(at: folder.url)
        let watching = Task { try await scanner.watch(rootID: root.id) }
        defer { watching.cancel() }
        let store = scanner.store
        func names() async throws -> Set<String> {
            let refs = try await store.assetRefs(for: AssetQuery())
            return try await Set(store.assets(ids: refs.map(\.id)).map(\.name))
        }
        try await Task.sleep(for: .milliseconds(800))
        try folder.write("sub/new.jpg")
        try folder.move("a.jpg", to: "b.jpg")
        #expect(try await eventually { try await names() == ["b.jpg", "new.jpg"] })
        let stored = try await store.root(id: root.id)
        #expect(stored.lastEventID != nil)
        #expect(stored.eventDatabaseUUID != nil)
    }
}
