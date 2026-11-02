import Foundation
import GRDB

/// Waveforms of library audio files share `cache.sqlite` with thumbnails (docs/ARCHITECTURE.md §10). They are
/// small (4 KB each) and not counted against the thumbnail cap; "Clear cache" removes them too.
public extension ThumbnailDiskCache {
    internal static func registerWaveformMigration(_ migrator: inout DatabaseMigrator) {
        migrator.registerMigration("v2-waveform") { db in
            try db.execute(sql: """
            CREATE TABLE waveform (
              asset_id INTEGER NOT NULL,
              mtime INTEGER NOT NULL,
              data BLOB NOT NULL,
              PRIMARY KEY (asset_id, mtime)
            );
            """)
        }
    }

    /// The stored waveform of an asset at its modification time (ms), if any.
    func waveform(assetID: Int64, modifiedAt: Int64) async throws -> Waveform? {
        try await writer.read { db in
            try Data.fetchOne(
                db, sql: "SELECT data FROM waveform WHERE asset_id = ? AND mtime = ?", arguments: [assetID, modifiedAt]
            )
        }.flatMap(Waveform.init(data:))
    }

    /// Stores a complete waveform, replacing those of older versions of the file.
    func storeWaveform(_ waveform: Waveform, assetID: Int64, modifiedAt: Int64) async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM waveform WHERE asset_id = ?", arguments: [assetID])
            try db.execute(
                sql: "INSERT INTO waveform (asset_id, mtime, data) VALUES (?, ?, ?)",
                arguments: [assetID, modifiedAt, waveform.data]
            )
        }
    }
}
