import GRDB
import JGModel

/// Flags (docs/FEATURES.md §12, DECISIONS D-57), kept in the library only (D-15: nothing is written to the files).
public extension LibraryStore {
    /// Sets `flag` on the assets; returns each one's previous flag (for undo).
    @discardableResult
    func setFlag(_ flag: AssetFlag, assetIDs: [Int64]) async throws -> [Int64: AssetFlag] {
        try await writer.write { db in
            let previous = try Self.fetchFlags(db, ids: assetIDs)
            for chunk in assetIDs.chunked(into: 500) {
                try db.execute(
                    sql: "UPDATE asset SET flag = ? WHERE id IN (\(databaseQuestionMarks(count: chunk.count)))",
                    arguments: StatementArguments([flag.rawValue]) + StatementArguments(chunk)
                )
            }
            return previous
        }
    }

    /// Puts back flags returned by `setFlag`.
    func restoreFlags(_ flags: [Int64: AssetFlag]) async throws {
        try await writer.write { db in
            for (id, flag) in flags {
                try db.execute(sql: "UPDATE asset SET flag = ? WHERE id = ?", arguments: [flag.rawValue, id])
            }
        }
    }

    /// The flags of the assets that exist.
    func flags(ids: [Int64]) async throws -> [Int64: AssetFlag] {
        try await writer.read { db in try Self.fetchFlags(db, ids: ids) }
    }

    private static func fetchFlags(_ db: Database, ids: [Int64]) throws -> [Int64: AssetFlag] {
        var flags: [Int64: AssetFlag] = [:]
        for chunk in ids.chunked(into: 500) {
            let rows = try Row.fetchAll(
                db, sql: "SELECT id, flag FROM asset WHERE id IN (\(databaseQuestionMarks(count: chunk.count)))",
                arguments: StatementArguments(chunk)
            )
            for row in rows {
                flags[row[0]] = AssetFlag(rawValue: row[1]) ?? AssetFlag.none
            }
        }
        return flags
    }
}
