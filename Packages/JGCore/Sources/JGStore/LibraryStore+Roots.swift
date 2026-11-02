import Foundation
import GRDB
import JGModel

public extension LibraryStore {
    /// Adds a library root and its top folder row. Never touches files.
    ///
    /// - Parameter path: absolute path with symlinks resolved.
    /// - Throws: `StoreError.rootAlreadyExists` or `.rootOverlapsExisting`.
    func addRoot(
        path: String,
        bookmark: Data? = nil,
        volumeUUID: String? = nil,
        isRecursive: Bool = true,
        isWatched: Bool = true,
        now: Date = Date()
    ) async throws -> RootFolder {
        let path = Self.normalized(path)
        return try await writer.write { db in
            for existing in try String.fetchAll(db, sql: "SELECT path FROM root_folder") {
                if existing == path {
                    throw StoreError.rootAlreadyExists(path: path)
                }
                if path.hasPrefix(existing + "/") || existing.hasPrefix(path + "/") {
                    throw StoreError.rootOverlapsExisting(path: path, existing: existing)
                }
            }
            var root = RootRecord(
                id: nil, path: path, bookmark: bookmark, volumeUuid: volumeUUID, eventDatabaseUuid: nil,
                lastEventId: nil, isRecursive: isRecursive, isWatched: isWatched, addedAt: now.millisecondsSince1970
            )
            try root.insert(db)
            guard let rootID = root.id else { throw StoreError.rootNotFound(id: 0) }
            var folder = FolderRecord(
                id: nil, rootId: rootID, parentId: nil, relPath: "",
                name: (path as NSString).lastPathComponent, state: AssetState.present.rawValue
            )
            try folder.insert(db)
            return root.model
        }
    }

    /// All roots, in the order they were added.
    func roots() async throws -> [RootFolder] {
        try await writer.read { db in
            try RootRecord.order(Column("id")).fetchAll(db).map(\.model)
        }
    }

    /// One root.
    func root(id: Int64) async throws -> RootFolder {
        try await writer.read { db in try Self.rootRecord(db, id: id).model }
    }

    /// Removes a root with all its folder and asset rows. Files on disk are untouched.
    func removeRoot(id: Int64) async throws {
        _ = try await writer.write { db in try RootRecord.deleteOne(db, key: id) }
    }

    /// Records the last fully processed FSEvents event id of a root.
    func updateEventState(rootID: Int64, lastEventID: UInt64, eventDatabaseUUID: String?) async throws {
        try await writer.write { db in
            try db.execute(
                sql: "UPDATE root_folder SET last_event_id = ?, event_database_uuid = ? WHERE id = ?",
                arguments: [Int64(bitPattern: lastEventID), eventDatabaseUUID, rootID]
            )
        }
    }

    internal static func rootRecord(_ db: Database, id: Int64) throws -> RootRecord {
        guard let root = try RootRecord.fetchOne(db, key: id) else { throw StoreError.rootNotFound(id: id) }
        return root
    }

    /// Paths are compared without a trailing slash.
    internal static func normalized(_ path: String) -> String {
        path.count > 1 && path.hasSuffix("/") ? String(path.dropLast()) : path
    }
}
