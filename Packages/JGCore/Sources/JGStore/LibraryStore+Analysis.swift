import Foundation
import GRDB
import JGModel

/// Tempo and key found in songs (D-106), by path, so any file opened counts, in the library or not. A row holds only
/// while the file keeps its size and modification time.
public extension LibraryStore {
    /// What was found in this version of the file, or nil.
    func audioAnalysis(path: String, size: Int64, modifiedAt: Date) async throws -> AudioAnalysis? {
        try await writer.read { db in
            let row = try Row.fetchOne(
                db, sql: "SELECT bpm, key_tonic, key_minor FROM audio_analysis WHERE path = ? AND size = ? AND mtime = ?",
                arguments: [path, size, modifiedAt.millisecondsSince1970]
            )
            return row.map { row in
                let tonic: Int? = row["key_tonic"]
                return AudioAnalysis(bpm: row["bpm"], key: tonic.map { MusicKey(tonic: $0, isMinor: row["key_minor"] != 0) })
            }
        }
    }

    /// Keeps `analysis` for this version of the file, replacing any earlier one.
    func saveAudioAnalysis(_ analysis: AudioAnalysis, path: String, size: Int64, modifiedAt: Date) async throws {
        try await writer.write { db in
            try db.execute(
                sql: """
                INSERT OR REPLACE INTO audio_analysis (path, size, mtime, bpm, key_tonic, key_minor)
                VALUES (?, ?, ?, ?, ?, ?)
                """,
                arguments: [
                    path, size, modifiedAt.millisecondsSince1970, analysis.bpm, analysis.key?.tonic,
                    analysis.key?.isMinor == true ? 1 : 0,
                ]
            )
        }
    }
}
