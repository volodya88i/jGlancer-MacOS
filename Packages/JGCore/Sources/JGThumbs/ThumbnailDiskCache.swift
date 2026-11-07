import Foundation
import GRDB
import JGModel

/// `cache.sqlite`: rebuildable thumbnails as encoded BLOBs, capped in size with least-recently-used
/// eviction (docs/ARCHITECTURE.md §4, §6), and waveforms (§10). Safe to delete at any time.
public final class ThumbnailDiskCache: Sendable {
    /// Default size cap (docs/FEATURES.md §14).
    public static let defaultLimitBytes: Int64 = 2 * 1024 * 1024 * 1024

    let writer: any DatabaseWriter
    private let limit: Mutex<Int64>
    /// Insertions between eviction checks.
    private static let evictionInterval = 64
    private let insertions = Mutex(0)

    /// Opens the cache at `url`; a corrupt file is deleted and recreated (it only holds derived data).
    public static func open(at url: URL, limitBytes: Int64 = defaultLimitBytes) throws -> ThumbnailDiskCache {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        do {
            return try ThumbnailDiskCache(writer: DatabasePool(path: url.path), limitBytes: limitBytes)
        } catch {
            for suffix in ["", "-wal", "-shm"] {
                try? FileManager.default.removeItem(atPath: url.path + suffix)
            }
            return try ThumbnailDiskCache(writer: DatabasePool(path: url.path), limitBytes: limitBytes)
        }
    }

    /// An in-memory cache, for tests.
    public static func inMemory(limitBytes: Int64 = defaultLimitBytes) throws -> ThumbnailDiskCache {
        try ThumbnailDiskCache(writer: DatabaseQueue(), limitBytes: limitBytes)
    }

    init(writer: any DatabaseWriter, limitBytes: Int64) throws {
        self.writer = writer
        limit = Mutex(limitBytes)
        try Self.migrator.migrate(writer)
    }

    private static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1-thumbs") { db in
            try db.execute(sql: """
            CREATE TABLE thumb (
              asset_id INTEGER NOT NULL,
              mtime INTEGER NOT NULL,
              bucket INTEGER NOT NULL,
              width INTEGER NOT NULL,
              height INTEGER NOT NULL,
              data BLOB NOT NULL,
              last_used INTEGER NOT NULL,
              PRIMARY KEY (asset_id, mtime, bucket)
            );
            CREATE INDEX thumb_last_used ON thumb(last_used);
            CREATE TABLE usage (id INTEGER PRIMARY KEY CHECK (id = 1), bytes INTEGER NOT NULL);
            INSERT INTO usage VALUES (1, 0);
            CREATE TRIGGER thumb_added AFTER INSERT ON thumb BEGIN
              UPDATE usage SET bytes = bytes + length(NEW.data);
            END;
            CREATE TRIGGER thumb_removed AFTER DELETE ON thumb BEGIN
              UPDATE usage SET bytes = bytes - length(OLD.data);
            END;
            CREATE TRIGGER thumb_replaced AFTER UPDATE OF data ON thumb BEGIN
              UPDATE usage SET bytes = bytes - length(OLD.data) + length(NEW.data);
            END;
            """)
        }
        registerWaveformMigration(&migrator)
        migrator.registerMigration("v3-display-p3") { db in
            // Thumbnails were sRGB before; they are made again in Display P3 as they are needed. Dropping the table is
            // instant where deleting row by row (the byte-counting trigger) is not.
            try db.execute(sql: """
            DROP TABLE thumb;
            CREATE TABLE thumb (
              asset_id INTEGER NOT NULL,
              mtime INTEGER NOT NULL,
              bucket INTEGER NOT NULL,
              width INTEGER NOT NULL,
              height INTEGER NOT NULL,
              data BLOB NOT NULL,
              last_used INTEGER NOT NULL,
              PRIMARY KEY (asset_id, mtime, bucket)
            );
            CREATE INDEX thumb_last_used ON thumb(last_used);
            UPDATE usage SET bytes = 0;
            CREATE TRIGGER thumb_added AFTER INSERT ON thumb BEGIN
              UPDATE usage SET bytes = bytes + length(NEW.data);
            END;
            CREATE TRIGGER thumb_removed AFTER DELETE ON thumb BEGIN
              UPDATE usage SET bytes = bytes - length(OLD.data);
            END;
            CREATE TRIGGER thumb_replaced AFTER UPDATE OF data ON thumb BEGIN
              UPDATE usage SET bytes = bytes - length(OLD.data) + length(NEW.data);
            END;
            """)
        }
        return migrator
    }

    /// The stored entry: encoded image data, or empty data meaning "this asset has no thumbnail".
    public func data(for key: ThumbnailKey, now: Date = Date()) async throws -> Data? {
        let nowMilliseconds = Self.milliseconds(now)
        let found = try await writer.read { db in
            try Row.fetchOne(
                db, sql: "SELECT data, last_used FROM thumb WHERE asset_id = ? AND mtime = ? AND bucket = ?",
                arguments: [key.assetID, key.modifiedAt, key.bucket.rawValue]
            ).map { (data: $0["data"] as Data, lastUsed: $0["last_used"] as Int64) }
        }
        // Recency is refreshed at most once a day per entry, so reads rarely write.
        if let found, nowMilliseconds - found.lastUsed > 86_400_000 {
            try await writer.write { db in
                try db.execute(
                    sql: "UPDATE thumb SET last_used = ? WHERE asset_id = ? AND mtime = ? AND bucket = ?",
                    arguments: [nowMilliseconds, key.assetID, key.modifiedAt, key.bucket.rawValue]
                )
            }
        }
        return found?.data
    }

    /// Stores an encoded thumbnail (or empty data for "none") and evicts old entries when over the cap.
    public func store(_ data: Data, width: Int, height: Int, for key: ThumbnailKey, now: Date = Date()) async throws {
        let nowMilliseconds = Self.milliseconds(now)
        try await writer.write { db in
            // An upsert, not INSERT OR REPLACE: REPLACE deletes without firing the byte-counting trigger.
            try db.execute(sql: """
            INSERT INTO thumb (asset_id, mtime, bucket, width, height, data, last_used)
            VALUES (?, ?, ?, ?, ?, ?, ?)
            ON CONFLICT (asset_id, mtime, bucket) DO UPDATE SET
              width = excluded.width, height = excluded.height, data = excluded.data, last_used = excluded.last_used
            """, arguments: [key.assetID, key.modifiedAt, key.bucket.rawValue, width, height, data, nowMilliseconds])
        }
        let due = insertions.withLock { count in
            count += 1
            return count % Self.evictionInterval == 0
        }
        if due {
            try await evictIfNeeded()
        }
    }

    /// Bytes of encoded thumbnails currently stored.
    public func usedBytes() async throws -> Int64 {
        try await writer.read { db in try Int64.fetchOne(db, sql: "SELECT bytes FROM usage") ?? 0 }
    }

    /// The size cap in bytes (Settings → Library).
    public var limitBytes: Int64 {
        limit.withLock { $0 }
    }

    /// Changes the cap; a smaller one evicts at once.
    public func setLimit(bytes: Int64) async throws {
        limit.withLock { $0 = bytes }
        try await evictIfNeeded()
    }

    /// Deletes least recently used entries until the cache is at 90 % of its cap.
    public func evictIfNeeded() async throws {
        let limitBytes = limitBytes
        let target = limitBytes * 9 / 10
        try await writer.write { db in
            let used = try Int64.fetchOne(db, sql: "SELECT bytes FROM usage") ?? 0
            guard used > limitBytes else { return }
            // Oldest first, just enough entries to get back to the target.
            var excess = used - target
            var victims: [Int64] = []
            let rows = try Row.fetchCursor(db, sql: "SELECT rowid, length(data) FROM thumb ORDER BY last_used, rowid")
            while excess > 0, let row = try rows.next() {
                victims.append(row[0])
                excess -= row[1] as Int64
            }
            for chunk in stride(from: 0, to: victims.count, by: 500).map({ Array(victims[$0 ..< min($0 + 500, victims.count)]) }) {
                try db.execute(
                    sql: "DELETE FROM thumb WHERE rowid IN (\(databaseQuestionMarks(count: chunk.count)))",
                    arguments: StatementArguments(chunk)
                )
            }
        }
    }

    /// Empties the cache ("Clear cache" in Settings).
    public func removeAll() async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM thumb")
            try db.execute(sql: "DELETE FROM waveform")
        }
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}
