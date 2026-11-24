import Foundation
import GRDB
import JGModel

/// Virtual albums (docs/FEATURES.md §6, ARCHITECTURE §13): lists of asset ids, so items follow the app's moves
/// and renames. Deleting an album or removing items never touches files. An item whose file vanished is not shown
/// (it cannot be opened), but keeps its place for `albumPlaceholderLifetime`: when the file comes back (a disk plugged
/// in again, an undone Trash) it is in its albums again (D-119); `purgeAlbumPlaceholders` drops older ones.
public extension LibraryStore {
    /// How long a vanished file keeps its place in its albums.
    static let albumPlaceholderLifetime: TimeInterval = 30 * 24 * 3600

    @discardableResult
    func createAlbum(name: String, now: Date = Date()) async throws -> Album {
        try await writer.write { db in
            let order = try Int64.fetchOne(db, sql: "SELECT COALESCE(MAX(sort_order), -1) + 1 FROM album") ?? 0
            try db.execute(
                sql: "INSERT INTO album (name, created_at, sort_order) VALUES (?, ?, ?)",
                arguments: [name, Self.ms(now), order]
            )
            return Album(id: db.lastInsertedRowID, name: name, createdAt: now, coverAssetID: nil, itemCount: 0)
        }
    }

    func renameAlbum(_ id: Int64, to name: String) async throws {
        try await writer.write { db in
            try db.execute(sql: "UPDATE album SET name = ? WHERE id = ?", arguments: [name, id])
        }
    }

    /// Deletes the album and its item list; the files are not touched.
    func deleteAlbum(_ id: Int64) async throws {
        try await writer.write { db in
            try db.execute(sql: "DELETE FROM album WHERE id = ?", arguments: [id])
        }
    }

    /// Every album in sidebar order.
    func albums() async throws -> [Album] {
        try await writer.read { db in try Self.fetchAlbums(db) }
    }

    /// Emits the albums now and after every change (names, items, covers).
    func observeAlbums() -> AsyncThrowingStream<[Album], Error> {
        observeValues { db in try Self.fetchAlbums(db) }
    }

    /// Emits, now and after every change, the albums each asset belongs to (menus mark "already added").
    func observeAlbumMemberships() -> AsyncThrowingStream<[Int64: Set<Int64>], Error> {
        observeValues { db in
            var memberships: [Int64: Set<Int64>] = [:]
            for row in try Row.fetchAll(db, sql: "SELECT asset_id, album_id FROM album_item") {
                memberships[row[0], default: []].insert(row[1])
            }
            return memberships
        }
    }

    /// Appends assets not yet in the album, in the given order; returns the ones added.
    @discardableResult
    func addToAlbum(_ albumID: Int64, assetIDs: [Int64], now: Date = Date()) async throws -> [Int64] {
        try await writer.write { db in
            let existing = try Set(Int64.fetchAll(db, sql: "SELECT asset_id FROM album_item WHERE album_id = ?", arguments: [albumID]))
            var next = try Int64.fetchOne(
                db, sql: "SELECT COALESCE(MAX(position), -1) + 1 FROM album_item WHERE album_id = ?", arguments: [albumID]
            ) ?? 0
            var added: [Int64] = []
            var seen = existing
            let insert = try db.makeStatement(
                sql: "INSERT INTO album_item (album_id, asset_id, position, added_at) VALUES (?, ?, ?, ?)"
            )
            for id in assetIDs where seen.insert(id).inserted {
                try insert.execute(arguments: [albumID, id, next, Self.ms(now)])
                next += 1
                added.append(id)
            }
            return added
        }
    }

    /// Removes items; returns where they were, for an undo.
    @discardableResult
    func removeFromAlbum(_ albumID: Int64, assetIDs: [Int64]) async throws -> [AlbumItemPosition] {
        try await writer.write { db in
            var removed: [AlbumItemPosition] = []
            for id in assetIDs {
                if let position = try Int64.fetchOne(
                    db, sql: "SELECT position FROM album_item WHERE album_id = ? AND asset_id = ?", arguments: [albumID, id]
                ) {
                    try db.execute(sql: "DELETE FROM album_item WHERE album_id = ? AND asset_id = ?", arguments: [albumID, id])
                    removed.append(AlbumItemPosition(assetID: id, position: position))
                }
            }
            return removed
        }
    }

    /// Puts removed items back where they were (undo of `removeFromAlbum`).
    func restoreToAlbum(_ albumID: Int64, items: [AlbumItemPosition], now: Date = Date()) async throws {
        try await writer.write { db in
            for item in items {
                try db.execute(sql: """
                INSERT OR IGNORE INTO album_item (album_id, asset_id, position, added_at)
                SELECT ?, ?, ?, ? WHERE EXISTS (SELECT 1 FROM asset WHERE id = ?)
                """, arguments: [albumID, item.assetID, item.position, Self.ms(now), item.assetID])
            }
        }
    }

    /// The album's item ids in order (vanished files that keep their place included).
    func albumOrder(_ albumID: Int64) async throws -> [Int64] {
        try await writer.read { db in
            try Int64.fetchAll(db, sql: "SELECT asset_id FROM album_item WHERE album_id = ? ORDER BY position", arguments: [albumID])
        }
    }

    /// Moves `assetIDs` (keeping their relative order) in front of `before`, or to the end when nil.
    func moveInAlbum(_ albumID: Int64, assetIDs: [Int64], before: Int64?) async throws {
        let order = try await albumOrder(albumID)
        let movingIDs = Set(assetIDs)
        let moving = order.filter(movingIDs.contains)
        var rest = order.filter { !movingIDs.contains($0) }
        let index = before.flatMap { rest.firstIndex(of: $0) } ?? rest.count
        rest.insert(contentsOf: moving, at: index)
        try await setAlbumOrder(albumID, rest)
    }

    /// Renumbers the album to `order` (ids not in the album are ignored; missing ones keep their place at the end).
    func setAlbumOrder(_ albumID: Int64, _ order: [Int64]) async throws {
        try await writer.write { db in
            let current = try Int64.fetchAll(
                db, sql: "SELECT asset_id FROM album_item WHERE album_id = ? ORDER BY position", arguments: [albumID]
            )
            let known = Set(current)
            let ordered = Set(order)
            let full = order.filter(known.contains) + current.filter { !ordered.contains($0) }
            let update = try db.makeStatement(sql: "UPDATE album_item SET position = ? WHERE album_id = ? AND asset_id = ?")
            for (position, id) in full.enumerated() {
                try update.execute(arguments: [position, albumID, id])
            }
        }
    }

    /// The album's cover; nil goes back to the first item.
    func setAlbumCover(_ albumID: Int64, assetID: Int64?) async throws {
        try await writer.write { db in
            try db.execute(sql: "UPDATE album SET cover_asset_id = ? WHERE id = ?", arguments: [assetID, albumID])
        }
    }

    /// Drops album items whose files vanished more than `albumPlaceholderLifetime` ago; returns how many.
    @discardableResult
    func purgeAlbumPlaceholders(now: Date = Date()) async throws -> Int {
        let cutoff = Self.ms(now.addingTimeInterval(-Self.albumPlaceholderLifetime))
        return try await writer.write { db in
            try db.execute(sql: """
            DELETE FROM album_item WHERE asset_id IN (SELECT id FROM asset WHERE state = 1 AND missing_since < ?)
            """, arguments: [cutoff])
            return db.changesCount
        }
    }

    // MARK: Fetching

    static func fetchAlbums(_ db: Database) throws -> [Album] {
        try Row.fetchAll(db, sql: """
        SELECT album.id, album.name, album.created_at,
          COALESCE(
            (SELECT a.id FROM asset a WHERE a.id = album.cover_asset_id AND a.state = 0),
            (SELECT i.asset_id FROM album_item i JOIN asset a ON a.id = i.asset_id
             WHERE i.album_id = album.id AND a.state = 0 ORDER BY i.position LIMIT 1)
          ) AS cover,
          (SELECT COUNT(*) FROM album_item i JOIN asset a ON a.id = i.asset_id WHERE i.album_id = album.id AND a.state = 0)
        FROM album ORDER BY album.sort_order, album.id
        """).map { row in
            Album(
                id: row[0], name: row[1], createdAt: Date(timeIntervalSince1970: Double(row[2] as Int64) / 1000),
                coverAssetID: row[3], itemCount: row[4]
            )
        }
    }

    /// The album's present items in its order, with the query's kinds, flag filter and search (D-119).
    static func fetchAlbumRefs(_ db: Database, albumID: Int64, query: AssetQuery) throws -> [AssetRef] {
        let kinds = query.kinds.map(\.rawValue).sorted()
        guard !kinds.isEmpty else { return [] }
        var conditions = ["album_item.album_id = ?", "asset.state = 0", "asset.kind IN (\(kinds.map(String.init).joined(separator: ",")))"]
        var arguments: StatementArguments = [albumID]
        if let flag = flagCondition(query.flagFilter) {
            conditions.append(flag)
        }
        if let search = searchCondition(query.searchText) {
            conditions.append(search.sql)
            arguments += search.arguments
        }
        conditions += viewConditions(query, includingHidden: false)
        return try Row.fetchAll(db, sql: """
        SELECT asset.id, asset.kind, asset.folder_id FROM album_item JOIN asset ON asset.id = album_item.asset_id
        WHERE \(conditions.joined(separator: " AND "))
        ORDER BY album_item.position, asset.id
        """, arguments: arguments).map { AssetRef(id: $0[0], kind: MediaKind(rawValue: $0[1]) ?? .photo, folderID: $0[2]) }
    }

    private static func ms(_ date: Date) -> Int64 {
        Int64((date.timeIntervalSince1970 * 1000).rounded())
    }
}
