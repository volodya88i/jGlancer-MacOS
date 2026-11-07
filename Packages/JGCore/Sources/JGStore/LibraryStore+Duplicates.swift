import Foundation
import GRDB
import JGModel

/// Copies of the same file found by the library's own facts (W-78): same size and same quick hash.
public struct DuplicateCandidates: Sendable {
    /// Each group holds two or more files of one size and quick hash, in id order.
    public let groups: [[Asset]]
    /// Files whose quick hash is not read yet (stage 2 still running); they may hide more copies.
    public let pending: Int
}

public extension LibraryStore {
    /// Groups of present files with the same size and quick hash, and how many files are still being read.
    func duplicateCandidates() async throws -> DuplicateCandidates {
        try await writer.read { db in
            let ids = try Int64.fetchAll(db, sql: """
            SELECT a.id FROM asset a
            JOIN (
              SELECT size, quick_hash FROM asset
              WHERE state = 0 AND quick_hash IS NOT NULL
              GROUP BY size, quick_hash HAVING COUNT(*) > 1
            ) d ON a.size = d.size AND a.quick_hash = d.quick_hash
            WHERE a.state = 0
            ORDER BY a.size, a.quick_hash, a.id
            """)
            let records = try AssetRecord.fetchAll(db, keys: ids)
            let directories = try Self.folderPaths(db, folderIDs: Set(records.map(\.folderId)))
            let byID = Dictionary(records.compactMap { record in record.id.map { ($0, record) } }) { first, _ in first }
            // The ids come ordered by size and hash: a group is a run of equal keys.
            var groups: [[Asset]] = []
            var lastKey: (size: Int64, hash: Data?)?
            for id in ids {
                guard let record = byID[id], let directory = directories[record.folderId] else { continue }
                let key = (size: record.size, hash: record.quickHash)
                if let lastKey, lastKey.size == key.size, lastKey.hash == key.hash {
                    groups[groups.count - 1].append(record.model(directory: directory))
                } else {
                    groups.append([record.model(directory: directory)])
                }
                lastKey = key
            }
            let pending = try Int.fetchOne(
                db, sql: "SELECT COUNT(*) FROM asset WHERE state = 0 AND quick_hash IS NULL AND meta_state = 0 AND cloud_only = 0"
            ) ?? 0
            return DuplicateCandidates(groups: groups.filter { $0.count > 1 }, pending: pending)
        }
    }
}
