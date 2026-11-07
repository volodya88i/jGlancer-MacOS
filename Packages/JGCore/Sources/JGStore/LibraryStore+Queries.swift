import Foundation
import GRDB
import JGModel

/// Counts describing the library, for status bars and benchmarks.
public struct LibraryStatistics: Equatable, Sendable {
    public var assetsByKind: [MediaKind: Int]
    public var missingAssets: Int
    public var pendingMetadata: Int
    public var folders: Int

    /// Present assets of every kind.
    public var presentAssets: Int {
        assetsByKind.values.reduce(0, +)
    }
}

public extension LibraryStore {
    /// The lean, sorted index of present assets matching `query` (docs/ARCHITECTURE.md §4).
    func assetRefs(for query: AssetQuery) async throws -> [AssetRef] {
        try await writer.read { db in try Self.fetchAssetRefs(db, query: query) }
    }

    /// The photos `query` shows, with folder and name, for finding image sequences (D-84); none for albums.
    func sequenceMembers(for query: AssetQuery) async throws -> [ImageSequences.Member] {
        if case .album = query.scope {
            return []
        }
        guard query.kinds.contains(.photo), let filter = Self.filter(for: query) else { return [] }
        return try await writer.read { db in
            let rows = try Row.fetchCursor(db, sql: """
            SELECT asset.id, asset.folder_id, asset.name FROM asset
            WHERE \(filter.sql) AND asset.kind = \(MediaKind.photo.rawValue)
            """, arguments: filter.arguments)
            var members: [ImageSequences.Member] = []
            while let row = try rows.next() {
                members.append(ImageSequences.Member(id: row[0], folderID: row[1], name: row[2]))
            }
            return members
        }
    }

    /// Full rows for `ids`, in the order of `ids`; unknown ids are skipped.
    func assets(ids: [Int64]) async throws -> [Asset] {
        try await writer.read { db in
            let records = try AssetRecord.fetchAll(db, keys: ids)
            let directories = try Self.folderPaths(db, folderIDs: Set(records.map(\.folderId)))
            var byID: [Int64: Asset] = [:]
            for record in records {
                guard let id = record.id, let directory = directories[record.folderId] else { continue }
                byID[id] = record.model(directory: directory)
            }
            return ids.compactMap { byID[$0] }
        }
    }

    /// Number and total size in bytes of the assets matching `query`.
    func totals(for query: AssetQuery) async throws -> (assets: Int, bytes: Int64) {
        try await writer.read { db in
            guard let filter = Self.filter(for: query) else { return (0, 0) }
            let row = try Row.fetchOne(
                db, sql: "SELECT COUNT(*), TOTAL(size) FROM asset WHERE \(filter.sql)", arguments: filter.arguments
            )
            return (row?[0] ?? 0, Int64((row?[1] as Double?) ?? 0))
        }
    }

    /// Total size in bytes of the given assets.
    func totalSize(ids: some Collection<Int64>) async throws -> Int64 {
        let ids = Array(ids)
        return try await writer.read { db in
            var total: Double = 0
            for chunk in ids.chunked(into: 500) {
                total += try Double.fetchOne(
                    db, sql: "SELECT TOTAL(size) FROM asset WHERE id IN (\(databaseQuestionMarks(count: chunk.count)))",
                    arguments: StatementArguments(chunk)
                ) ?? 0
            }
            return Int64(total)
        }
    }

    /// Absolute file URL of an asset, or nil if the id is unknown.
    func fileURL(assetID: Int64) async throws -> URL? {
        try await writer.read { db in
            let path = try String.fetchOne(db, sql: """
            SELECT root_folder.path || '/' || CASE folder.rel_path WHEN '' THEN '' ELSE folder.rel_path || '/' END || asset.name
            FROM asset JOIN folder ON folder.id = asset.folder_id JOIN root_folder ON root_folder.id = folder.root_id
            WHERE asset.id = ?
            """, arguments: [assetID])
            return path.map { URL(fileURLWithPath: $0) }
        }
    }

    /// Folders of a root (present ones unless `includeMissing`), sorted by relative path.
    func folders(rootID: Int64, includeMissing: Bool = false) async throws -> [Folder] {
        try await writer.read { db in try Self.fetchFolders(db, rootID: rootID, includeMissing: includeMissing) }
    }

    /// Counts by kind and state.
    func statistics() async throws -> LibraryStatistics {
        try await writer.read { db in
            var byKind: [MediaKind: Int] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT kind, COUNT(*) FROM asset WHERE state = 0 GROUP BY kind") {
                if let kind = MediaKind(rawValue: row[0]) {
                    byKind[kind] = row[1]
                }
            }
            return try LibraryStatistics(
                assetsByKind: byKind,
                missingAssets: Int.fetchOne(db, sql: "SELECT COUNT(*) FROM asset WHERE state = 1") ?? 0,
                pendingMetadata: Int.fetchOne(
                    db, sql: "SELECT COUNT(*) FROM asset WHERE meta_state = 0 AND state = 0 AND cloud_only = 0"
                ) ?? 0,
                folders: Int.fetchOne(db, sql: "SELECT COUNT(*) FROM folder WHERE state = 0") ?? 0
            )
        }
    }

    /// Emits the asset index for `query` now and after every change that affects it.
    func observeAssetRefs(_ query: AssetQuery) -> AsyncThrowingStream<[AssetRef], Error> {
        observe { db in try Self.fetchAssetRefs(db, query: query) }
    }

    /// Emits a root's present folders and the ones holding media themselves, now and after every change: the
    /// sidebar shows a subfolder only while it or a folder below holds media (D-78).
    func observeFolderListing(rootID: Int64) -> AsyncThrowingStream<FolderContents, Error> {
        observe { db in
            let folders = try Self.fetchFolders(db, rootID: rootID, includeMissing: false)
            let withMedia = try Set(Int64.fetchAll(db, sql: """
            SELECT folder.id FROM folder
            WHERE folder.root_id = ? AND folder.state = 0
              AND EXISTS (SELECT 1 FROM asset WHERE asset.folder_id = folder.id AND asset.state = 0)
            """, arguments: [rootID]))
            return FolderContents(folders: folders, withMedia: withMedia)
        }
    }

    /// Emits the roots now and after every change.
    func observeRoots() -> AsyncThrowingStream<[RootFolder], Error> {
        observe { db in try RootRecord.order(Column("id")).fetchAll(db).map(\.model) }
    }
}

extension LibraryStore {
    func observeValues<Value: Sendable & Equatable>(
        _ fetch: @escaping @Sendable (Database) throws -> Value
    ) -> AsyncThrowingStream<Value, Error> {
        observe(fetch)
    }

    private func observe<Value: Sendable & Equatable>(
        _ fetch: @escaping @Sendable (Database) throws -> Value
    ) -> AsyncThrowingStream<Value, Error> {
        let values = ValueObservation.tracking(fetch).removeDuplicates().values(in: writer)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    for try await value in values {
                        continuation.yield(value)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    static func fetchFolders(_ db: Database, rootID: Int64, includeMissing: Bool) throws -> [Folder] {
        var request = FolderRecord.filter(Column("root_id") == rootID)
        if !includeMissing {
            request = request.filter(Column("state") == AssetState.present.rawValue)
        }
        return try request.order(Column("rel_path")).fetchAll(db).map(\.model)
    }

    /// Absolute paths of folders by id.
    static func folderPaths(_ db: Database, folderIDs: Set<Int64>) throws -> [Int64: String] {
        var paths: [Int64: String] = [:]
        for chunk in Array(folderIDs).chunked(into: 500) {
            let rows = try Row.fetchAll(db, sql: """
            SELECT folder.id, folder.rel_path, root_folder.path FROM folder
            JOIN root_folder ON root_folder.id = folder.root_id
            WHERE folder.id IN (\(databaseQuestionMarks(count: chunk.count)))
            """, arguments: StatementArguments(chunk))
            for row in rows {
                paths[row[0]] = absolutePath(rootPath: row[2], relativePath: row[1])
            }
        }
        return paths
    }

    /// WHERE clause selecting the present assets of `query`; nil when the query matches nothing.
    static func filter(for query: AssetQuery) -> (sql: String, arguments: StatementArguments)? {
        let kinds = query.kinds.map(\.rawValue).sorted()
        guard !kinds.isEmpty else { return nil }
        var conditions = ["asset.state = 0", "asset.kind IN (\(kinds.map(String.init).joined(separator: ",")))"]
        var arguments: StatementArguments = []
        if let scope = scopeCondition(query.scope) {
            conditions.append(scope.sql)
            arguments += [scope.folderOrRootID]
        }
        if let flag = flagCondition(query.flagFilter) {
            conditions.append(flag)
        }
        if let search = searchCondition(query.searchText) {
            conditions.append(search.sql)
            arguments += search.arguments
        }
        return (conditions.joined(separator: " AND "), arguments)
    }

    static func flagCondition(_ filter: AssetQuery.FlagFilter?) -> String? {
        switch filter {
        case nil: nil
        case .flagged: "asset.flag != 0"
        case let .only(flag): "asset.flag = \(flag.rawValue)"
        }
    }

    /// Three characters or more use the trigram index (a quoted phrase); shorter text a plain `LIKE`.
    static func searchCondition(_ text: String?) -> (sql: String, arguments: StatementArguments)? {
        guard let text else { return nil }
        if text.count >= 3 {
            return ("asset.id IN (SELECT rowid FROM asset_search WHERE asset_search MATCH ?)",
                    ["\"" + text.replacingOccurrences(of: "\"", with: "\"\"") + "\""])
        }
        // SQLite's LIKE ignores case for ASCII letters only: other letters (Cyrillic, accented) are tried in each case,
        // as the trigram search does from three characters on. At most two characters, so at most four patterns.
        let patterns = caseVariants(of: text).map { variant in
            "%" + variant.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "%", with: "\\%").replacingOccurrences(of: "_", with: "\\_") + "%"
        }
        let sql = patterns.map { _ in "asset.name LIKE ? ESCAPE '\\'" }.joined(separator: " OR ")
        return ("(\(sql))", StatementArguments(patterns))
    }

    /// `text` with each non-ASCII letter in lower and upper case, every combination.
    static func caseVariants(of text: String) -> [String] {
        text.reduce([""]) { variants, character in
            let forms = character.isASCII ? [String(character)]
                : Array(Set([String(character).lowercased(), String(character).uppercased(), String(character)])).sorted()
            return variants.flatMap { prefix in forms.map { prefix + $0 } }
        }
    }

    static func fetchAssetRefs(_ db: Database, query: AssetQuery) throws -> [AssetRef] {
        if case let .album(albumID) = query.scope {
            return try fetchAlbumRefs(db, albumID: albumID, query: query)
        }
        guard let filter = filter(for: query) else { return [] }
        let direction = query.ascending ? "ASC" : "DESC"
        let sql = """
        SELECT asset.id, asset.kind, asset.folder_id FROM asset
        WHERE \(filter.sql)
        ORDER BY \(orderColumns(query.sort).map { "\($0) \(direction)" }.joined(separator: ", "))
        """
        var refs: [AssetRef] = []
        let rows = try Row.fetchCursor(db, sql: sql, arguments: filter.arguments)
        while let row = try rows.next() {
            refs.append(AssetRef(id: row[0], kind: MediaKind(rawValue: row[1]) ?? .photo, folderID: row[2]))
        }
        return refs
    }

    /// SQL restricting assets to a scope, with its single id argument; nil for the whole library.
    private static func scopeCondition(_ scope: AssetQuery.Scope) -> (sql: String, folderOrRootID: Int64)? {
        switch scope {
        case .library:
            nil
        case let .root(id):
            ("asset.folder_id IN (SELECT id FROM folder WHERE root_id = ?)", id)
        case let .album(id):
            ("asset.id IN (SELECT asset_id FROM album_item WHERE album_id = ?)", id)
        case let .folder(id, false):
            ("asset.folder_id = ?", id)
        case let .folder(id, true):
            // Subtree via a range on rel_path ("a/b/" ..< "a/b0"), which uses the (root_id, rel_path) index.
            ("""
            asset.folder_id IN (
              SELECT f.id FROM folder f JOIN folder p ON p.id = ? AND f.root_id = p.root_id
              WHERE f.id = p.id OR p.rel_path = '' OR (f.rel_path >= p.rel_path || '/' AND f.rel_path < p.rel_path || '0'))
            """, id)
        }
    }

    /// Sort columns; ties fall back to natural name order, then id.
    private static func orderColumns(_ sort: AssetQuery.Sort) -> [String] {
        switch sort {
        case .name: ["asset.name_key", "asset.name", "asset.id"]
        case .dateModified: ["asset.mtime", "asset.name_key", "asset.id"]
        case .dateCaptured: ["COALESCE(asset.captured_at, asset.mtime)", "asset.name_key", "asset.id"]
        case .size: ["asset.size", "asset.name_key", "asset.id"]
        case .kind: ["asset.kind", "asset.name_key", "asset.id"]
        }
    }
}
