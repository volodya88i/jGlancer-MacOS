import Foundation
import JGModel
import JGTestSupport
import Testing
@testable import JGStore

struct RecoveryTests {
    @Test func aHealthyLibraryOpensAsItIsAndBacksUpOncePerDay() async throws {
        let folder = try TemporaryDirectory()
        let url = folder.url.appendingPathComponent("library.sqlite")
        let backup = folder.url.appendingPathComponent("library-backup.sqlite")
        let (store, recovery) = try LibraryStore.openWithRecovery(at: url, backup: backup)
        #expect(recovery == nil)
        _ = try await store.addRoot(path: "/lib")
        #expect(try await store.backup(to: backup, ifOlderThan: 86400))
        #expect(try await !store.backup(to: backup, ifOlderThan: 86400))
        #expect(try await store.backup(to: backup, ifOlderThan: 86400, now: Date().addingTimeInterval(90000)))
        let copy = try LibraryStore.open(at: backup)
        #expect(try await copy.roots().count == 1)
    }

    @Test func aDamagedLibraryIsSetAsideAndTheBackupTakesItsPlace() async throws {
        let folder = try TemporaryDirectory()
        let url = folder.url.appendingPathComponent("library.sqlite")
        let backup = folder.url.appendingPathComponent("library-backup.sqlite")
        do {
            let store = try LibraryStore.open(at: url)
            _ = try await store.addRoot(path: "/kept")
            try await store.backup(to: backup, ifOlderThan: 0)
        }
        for suffix in ["-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
        try Data(repeating: 0x42, count: 8192).write(to: url)
        let (store, recovery) = try LibraryStore.openWithRecovery(at: url, backup: backup)
        guard case let .restoredFromBackup(_, damaged) = recovery else {
            Issue.record("expected a restore, got \(String(describing: recovery))")
            return
        }
        #expect(try await store.roots().map(\.path) == ["/kept"])
        // The damaged file is kept, byte for byte.
        #expect(try Data(contentsOf: damaged) == Data(repeating: 0x42, count: 8192))
    }

    @Test func withoutABackupANewLibraryStartsAndTheDamagedFileStays() async throws {
        let folder = try TemporaryDirectory()
        let url = folder.url.appendingPathComponent("library.sqlite")
        try Data(repeating: 0x13, count: 4096).write(to: url)
        let (store, recovery) = try LibraryStore.openWithRecovery(
            at: url, backup: folder.url.appendingPathComponent("missing-backup.sqlite")
        )
        guard case let .startedEmpty(damaged) = recovery else {
            Issue.record("expected a fresh start")
            return
        }
        #expect(try await store.roots().isEmpty)
        #expect(FileManager.default.fileExists(atPath: damaged.path))
    }
}
