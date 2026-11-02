import Foundation
import GRDB
import JGModel

/// Index updates made by the app's own file operations, in the same logical step as the file change
/// (docs/ARCHITECTURE.md §12): a moved or renamed file keeps its asset id. FSEvents reconcile later anyway.
public extension LibraryStore {
    /// The asset at `source` now lives at `destination` (both canonical paths). Inside the library the row moves
    /// (same id, folder rows created as needed); outside it becomes a tombstone. Returns the asset id, if any.
    @discardableResult
    func moveAsset(from source: String, to destination: String, now: Date = Date()) async throws -> Int64? {
        let source = Self.normalized(source)
        let destination = Self.normalized(destination)
        return try await writer.write { db in
            guard var asset = try Self.presentAsset(db, at: source) else { return nil }
            guard let (rootID, relative) = try Self.rootRelative(db, path: destination) else {
                asset.state = AssetState.missing.rawValue
                asset.missingSince = Self.milliseconds(now)
                try asset.update(db)
                return asset.id
            }
            let folder = try Self.ensureFolder(db, rootID: rootID, relativePath: (relative as NSString).deletingLastPathComponent)
            guard let folderID = folder.id else { return asset.id }
            let name = (relative as NSString).lastPathComponent
            // A tombstone of a replaced file may hold the name.
            try db.execute(
                sql: "DELETE FROM asset WHERE folder_id = ? AND name = ? AND state = ? AND id != ?",
                arguments: [folderID, name, AssetState.missing.rawValue, asset.id]
            )
            asset.folderId = folderID
            asset.name = name
            asset.nameKey = NaturalSortKey.make(name)
            try asset.update(db)
            return asset.id
        }
    }

    /// The file at `path` went to the Trash: its asset becomes a tombstone (kept for a restore).
    func markMissing(at path: String, now: Date = Date()) async throws {
        let path = Self.normalized(path)
        try await writer.write { db in
            guard var asset = try Self.presentAsset(db, at: path) else { return }
            asset.state = AssetState.missing.rawValue
            asset.missingSince = Self.milliseconds(now)
            try asset.update(db)
        }
    }

    /// A file came back at `path` (restored from the Trash): the tombstone there becomes present again, same id.
    @discardableResult
    func revive(at path: String) async throws -> Int64? {
        let path = Self.normalized(path)
        return try await writer.write { db in
            guard let (rootID, relative) = try Self.rootRelative(db, path: path),
                  let folder = try FolderRecord
                  .filter(Column("root_id") == rootID && Column("rel_path") == (relative as NSString).deletingLastPathComponent)
                  .fetchOne(db),
                  var asset = try AssetRecord
                  .filter(Column("folder_id") == folder.id && Column("name") == (relative as NSString).lastPathComponent)
                  .fetchOne(db)
            else { return nil }
            asset.state = AssetState.present.rawValue
            asset.missingSince = nil
            try asset.update(db)
            if folder.state != AssetState.present.rawValue {
                _ = try Self.ensureFolder(db, rootID: rootID, relativePath: folder.relPath)
            }
            return asset.id
        }
    }

    private static func presentAsset(_ db: Database, at path: String) throws -> AssetRecord? {
        guard let (rootID, relative) = try rootRelative(db, path: path) else { return nil }
        return try AssetRecord.fetchOne(db, sql: """
        SELECT asset.* FROM asset JOIN folder ON folder.id = asset.folder_id
        WHERE folder.root_id = ? AND folder.rel_path = ? AND asset.name = ? AND asset.state = 0
        """, arguments: [rootID, (relative as NSString).deletingLastPathComponent, (relative as NSString).lastPathComponent])
    }

    /// The root containing `path` and the path relative to it.
    private static func rootRelative(_ db: Database, path: String) throws -> (Int64, String)? {
        let roots = try RootRecord.fetchAll(db)
        guard let root = roots.first(where: { path.hasPrefix($0.path + "/") }), let id = root.id else { return nil }
        return (id, String(path.dropFirst(root.path.count + 1)))
    }

    private static func milliseconds(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}
