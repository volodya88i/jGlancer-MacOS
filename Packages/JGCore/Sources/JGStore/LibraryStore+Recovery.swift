import Foundation
import GRDB

/// What happened when the library database could not be used as it was (docs/ARCHITECTURE.md §20).
public enum LibraryRecovery: Equatable, Sendable {
    /// The damaged file was set aside and the last backup (made at `backupDate`) put in its place.
    case restoredFromBackup(backupDate: Date, damagedCopy: URL)
    /// No usable backup: a new, empty library; the damaged file was set aside.
    case startedEmpty(damagedCopy: URL)
}

/// Opening with a safety net, and the daily backup. Nothing is ever deleted: a damaged database is renamed
/// `library-damaged-<date>.sqlite` next to it, so its albums and flags can still be rescued by hand.
public extension LibraryStore {
    /// Opens `url`; if it is not a database or fails its integrity check, sets it aside and opens the backup at
    /// `backup` instead (or a new library when there is none that works).
    static func openWithRecovery(at url: URL, backup: URL, now: Date = Date()) throws -> (LibraryStore, LibraryRecovery?) {
        if let store = try? open(at: url), (try? store.isIntact()) == true {
            return (store, nil)
        }
        let damaged = try setAside(url, now: now)
        if FileManager.default.fileExists(atPath: backup.path) {
            let backupDate = (try? backup.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? now
            try FileManager.default.copyItem(at: backup, to: url)
            if let store = try? open(at: url), (try? store.isIntact()) == true {
                return (store, .restoredFromBackup(backupDate: backupDate, damagedCopy: damaged))
            }
            // The backup is no good either: keep it beside the damaged one and start over.
            _ = try setAside(url, now: now.addingTimeInterval(1))
        }
        return try (open(at: url), .startedEmpty(damagedCopy: damaged))
    }

    /// `PRAGMA quick_check` says "ok".
    func isIntact() throws -> Bool {
        try writer.read { db in try String.fetchOne(db, sql: "PRAGMA quick_check") == "ok" }
    }

    /// Writes a consistent copy of the library to `backup` (via a temporary file, then a swap) when the last
    /// backup is older than `maxAge` or missing. Returns true when a new backup was made.
    @discardableResult
    func backup(to backup: URL, ifOlderThan maxAge: TimeInterval, now: Date = Date()) async throws -> Bool {
        if let date = (try? backup.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
           now.timeIntervalSince(date) < maxAge
        {
            return false
        }
        let temporary = backup.deletingLastPathComponent().appendingPathComponent(".\(backup.lastPathComponent).\(UUID().uuidString)")
        try await writer.writeWithoutTransaction { db in
            try db.execute(sql: "VACUUM INTO ?", arguments: [temporary.path])
        }
        if FileManager.default.fileExists(atPath: backup.path) {
            _ = try FileManager.default.replaceItemAt(backup, withItemAt: temporary)
        } else {
            try FileManager.default.moveItem(at: temporary, to: backup)
        }
        return true
    }

    /// Renames the database and its WAL files to `library-damaged-<date>…`; returns the new database path.
    private static func setAside(_ url: URL, now: Date) throws -> URL {
        let stamp = ISO8601DateFormatter().string(from: now).replacingOccurrences(of: ":", with: "-")
        let base = url.deletingPathExtension().lastPathComponent + "-damaged-" + stamp
        let target = url.deletingLastPathComponent().appendingPathComponent(base + "." + url.pathExtension)
        for suffix in ["", "-wal", "-shm"] where FileManager.default.fileExists(atPath: url.path + suffix) {
            try FileManager.default.moveItem(atPath: url.path + suffix, toPath: target.path + suffix)
        }
        return target
    }
}
