import Foundation
import GRDB
import JGModel

public extension LibraryStore {
    /// Reconciles one directory listing with the database in a single transaction:
    /// adds, updates, tombstones, revives, and recognizes external moves (docs/ARCHITECTURE.md §5, §13).
    func applyDirectoryScan(_ scan: DirectoryScan, probe: some FileProbe) async throws -> DirectoryScanResult {
        try await writer.write { db in try Self.reconcile(db, scan: scan, probe: probe) }
    }
}

extension LibraryStore {
    static func reconcile(_ db: Database, scan: DirectoryScan, probe: some FileProbe) throws -> DirectoryScanResult {
        let root = try rootRecord(db, id: scan.rootID)
        let now = scan.scannedAt.millisecondsSince1970
        guard let folderID = try ensureFolder(db, rootID: scan.rootID, relativePath: scan.relativePath).id else {
            throw StoreError.rootNotFound(id: scan.rootID)
        }
        var result = DirectoryScanResult(folderID: folderID)
        let existing = try AssetRecord.filter(Column("folder_id") == folderID).fetchAll(db)
        // Vanished files become tombstones first, so a rename inside this folder can match them below.
        try tombstoneVanished(db, existing: existing, scan: scan, now: now, result: &result)
        let newFiles = try refreshKnown(db, existing: existing, scan: scan, now: now, result: &result)
        let target = TargetFolder(
            id: folderID,
            path: absolutePath(rootPath: root.path, relativePath: scan.relativePath),
            volumeUUID: root.volumeUuid,
            now: now
        )
        try addOrMatch(db, newFiles: newFiles, into: target, probe: probe, result: &result)
        try tombstoneRemovedSubfolders(db, scan: scan, folderID: folderID, now: now, result: &result)
        return result
    }

    private static func tombstoneVanished(
        _ db: Database, existing: [AssetRecord], scan: DirectoryScan, now: Int64, result: inout DirectoryScanResult
    ) throws {
        let scannedNames = Set(scan.files.map(\.name))
        for var record in existing where record.state == AssetState.present.rawValue && !scannedNames.contains(record.name) {
            record.state = AssetState.missing.rawValue
            record.missingSince = now
            try record.update(db)
            result.missing += 1
        }
    }

    /// Updates or revives rows whose name is already known; returns the files with new names.
    private static func refreshKnown(
        _ db: Database, existing: [AssetRecord], scan: DirectoryScan, now: Int64, result: inout DirectoryScanResult
    ) throws -> [ScannedFile] {
        let byName = Dictionary(existing.map { ($0.name, $0) }, uniquingKeysWith: { first, _ in first })
        var newFiles: [ScannedFile] = []
        for file in scan.files {
            guard var record = byName[file.name] else {
                newFiles.append(file)
                continue
            }
            let sameContent = record.size == file.size && record.mtime == file.modifiedAt.millisecondsSince1970
            let wasMissing = record.state == AssetState.missing.rawValue
            if sameContent, !wasMissing {
                let inode = file.inode.map(Int64.init(bitPattern:))
                if record.inode != inode {
                    record.inode = inode
                    try record.update(db)
                }
                result.unchanged += 1
                continue
            }
            if !sameContent {
                record.resetMetadata()
            }
            apply(file, to: &record, now: now)
            try record.update(db)
            if wasMissing {
                result.revived += 1
            } else {
                result.updated += 1
            }
        }
        return newFiles
    }

    /// New names: an external move or rename of a known asset (keeps its id), or a new asset.
    /// The folder new files are reconciled into, and the scan time.
    private struct TargetFolder {
        let id: Int64
        let path: String
        let volumeUUID: String?
        let now: Int64
    }

    private static func addOrMatch(
        _ db: Database, newFiles: [ScannedFile], into folder: TargetFolder, probe: some FileProbe,
        result: inout DirectoryScanResult
    ) throws {
        let now = folder.now
        guard !newFiles.isEmpty else { return }
        let candidates = try identityCandidates(db, for: newFiles, volumeUUID: folder.volumeUUID)
        var claimed = Set<Int64>()
        for file in newFiles {
            let filePath = folder.path + "/" + file.name
            let facts = IdentityMatcher.NewFile(
                size: file.size, modifiedAt: file.modifiedAt.millisecondsSince1970, inode: file.inode
            )
            let matchID = IdentityMatcher.match(
                facts, candidates: candidates, claimed: claimed, probe: probe,
                newFileHash: { probe.quickHash(atPath: filePath) }
            )
            if let matchID, var record = try AssetRecord.fetchOne(db, key: matchID) {
                record.folderId = folder.id
                record.name = file.name
                record.nameKey = NaturalSortKey.make(file.name)
                apply(file, to: &record, now: now)
                try record.update(db)
                claimed.insert(matchID)
                result.moved += 1
            } else {
                var record = AssetRecord(
                    id: nil, folderId: folder.id, name: file.name, nameKey: NaturalSortKey.make(file.name),
                    kind: file.kind.rawValue, uti: file.typeIdentifier, size: file.size,
                    mtime: file.modifiedAt.millisecondsSince1970, birthTime: file.createdAt?.millisecondsSince1970,
                    inode: file.inode.map(Int64.init(bitPattern:)), state: AssetState.present.rawValue,
                    metaState: MetadataState.pending.rawValue, indexedAt: now
                )
                try record.insert(db)
                result.added += 1
            }
        }
    }

    private static func tombstoneRemovedSubfolders(
        _ db: Database, scan: DirectoryScan, folderID: Int64, now: Int64, result: inout DirectoryScanResult
    ) throws {
        let present = Set(scan.subdirectories)
        let children = try FolderRecord
            .filter(Column("parent_id") == folderID && Column("state") == AssetState.present.rawValue)
            .fetchAll(db)
        for child in children where !present.contains(child.name) {
            result.missing += try markSubtreeMissing(db, rootID: scan.rootID, relativePath: child.relPath, now: now)
            result.removedSubfolders += 1
        }
    }

    /// Copies stage-1 facts onto a row and marks it present.
    private static func apply(_ file: ScannedFile, to record: inout AssetRecord, now: Int64) {
        record.kind = file.kind.rawValue
        record.uti = file.typeIdentifier
        record.size = file.size
        record.mtime = file.modifiedAt.millisecondsSince1970
        record.birthTime = file.createdAt?.millisecondsSince1970
        record.inode = file.inode.map(Int64.init(bitPattern:))
        record.state = AssetState.present.rawValue
        record.missingSince = nil
        record.indexedAt = now
    }

    /// Existing assets that could be one of `files`: same inode, or a tombstone of the same size.
    private static func identityCandidates(
        _ db: Database, for files: [ScannedFile], volumeUUID: String?
    ) throws -> [IdentityCandidate] {
        let inodes = Array(Set(files.compactMap(\.inode).map(Int64.init(bitPattern:))))
        let sizes = Array(Set(files.map(\.size)))
        var rows: [Row] = []
        let select = """
        SELECT asset.id, asset.inode, asset.size, asset.mtime, asset.quick_hash, asset.state, asset.name,
               folder.rel_path, root_folder.path, root_folder.volume_uuid
        FROM asset JOIN folder ON folder.id = asset.folder_id JOIN root_folder ON root_folder.id = folder.root_id
        """
        for chunk in inodes.chunked(into: 500) {
            let marks = databaseQuestionMarks(count: chunk.count)
            rows += try Row.fetchAll(db, sql: "\(select) WHERE asset.inode IN (\(marks))", arguments: StatementArguments(chunk))
        }
        for chunk in sizes.chunked(into: 500) {
            let marks = databaseQuestionMarks(count: chunk.count)
            rows += try Row.fetchAll(
                db,
                sql: "\(select) WHERE asset.state = 1 AND asset.quick_hash IS NOT NULL AND asset.size IN (\(marks))",
                arguments: StatementArguments(chunk)
            )
        }
        var seen = Set<Int64>()
        return rows.compactMap { row in
            let id: Int64 = row["id"]
            guard seen.insert(id).inserted else { return nil }
            let candidateVolume: String? = row["volume_uuid"]
            let inode: Int64? = row["inode"]
            return IdentityCandidate(
                id: id,
                inode: inode.map { UInt64(bitPattern: $0) },
                size: row["size"],
                modifiedAt: row["mtime"],
                quickHash: row["quick_hash"],
                isMissing: row["state"] == AssetState.missing.rawValue,
                isSameVolume: volumeUUID == nil || candidateVolume == nil || volumeUUID == candidateVolume,
                path: absolutePath(rootPath: row["path"], relativePath: row["rel_path"]) + "/" + (row["name"] as String)
            )
        }
    }

    /// The folder row for `relativePath`, created (with its parents) or revived as needed.
    static func ensureFolder(_ db: Database, rootID: Int64, relativePath: String) throws -> FolderRecord {
        if var existing = try FolderRecord
            .filter(Column("root_id") == rootID && Column("rel_path") == relativePath)
            .fetchOne(db)
        {
            if existing.state != AssetState.present.rawValue {
                existing.state = AssetState.present.rawValue
                try existing.update(db)
            }
            return existing
        }
        let root = try rootRecord(db, id: rootID)
        var parentID: Int64?
        var name = (root.path as NSString).lastPathComponent
        if !relativePath.isEmpty {
            let parentPath = (relativePath as NSString).deletingLastPathComponent
            parentID = try ensureFolder(db, rootID: rootID, relativePath: parentPath).id
            name = (relativePath as NSString).lastPathComponent
        }
        var folder = FolderRecord(
            id: nil, rootId: rootID, parentId: parentID, relPath: relativePath, name: name,
            state: AssetState.present.rawValue
        )
        try folder.insert(db)
        return folder
    }

    /// Tombstones a folder subtree and its present assets; returns the number of assets tombstoned.
    static func markSubtreeMissing(_ db: Database, rootID: Int64, relativePath: String, now: Int64) throws -> Int {
        let subtree = """
        SELECT id FROM folder WHERE root_id = :root
          AND (rel_path = :path OR (rel_path >= :path || '/' AND rel_path < :path || '0'))
        """
        let arguments: StatementArguments = ["root": rootID, "path": relativePath, "now": now]
        try db.execute(
            sql: "UPDATE asset SET state = 1, missing_since = :now WHERE state = 0 AND folder_id IN (\(subtree))",
            arguments: arguments
        )
        let tombstoned = db.changesCount
        try db.execute(sql: "UPDATE folder SET state = 1 WHERE id IN (\(subtree))", arguments: arguments)
        return tombstoned
    }

    static func absolutePath(rootPath: String, relativePath: String) -> String {
        relativePath.isEmpty ? rootPath : rootPath + "/" + relativePath
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map { Array(self[$0 ..< Swift.min($0 + size, count)]) }
    }
}
