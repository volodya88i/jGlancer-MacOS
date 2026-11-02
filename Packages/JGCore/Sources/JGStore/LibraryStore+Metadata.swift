import Foundation
import GRDB
import JGModel

/// An asset waiting for stage-2 metadata extraction.
public struct PendingMetadataItem: Hashable, Sendable {
    public let id: Int64
    public let url: URL
    public let kind: MediaKind
    /// Modification date seen at stage 1; results are saved only if the file did not change since.
    public let modifiedAt: Date
}

/// Stage-2 results for one asset.
public struct MetadataUpdate: Hashable, Sendable {
    public let id: Int64
    public let modifiedAt: Date
    public let state: MetadataState
    public let width: Int?
    public let height: Int?
    public let orientation: Int?
    public let duration: Double?
    public let frameRate: Double?
    public let codec: String?
    public let capturedAt: Date?
    public let quickHash: Data?

    public init(
        id: Int64, modifiedAt: Date, state: MetadataState, width: Int? = nil, height: Int? = nil,
        orientation: Int? = nil, duration: Double? = nil, frameRate: Double? = nil, codec: String? = nil,
        capturedAt: Date? = nil, quickHash: Data? = nil
    ) {
        self.id = id
        self.modifiedAt = modifiedAt
        self.state = state
        self.width = width
        self.height = height
        self.orientation = orientation
        self.duration = duration
        self.frameRate = frameRate
        self.codec = codec
        self.capturedAt = capturedAt
        self.quickHash = quickHash
    }
}

public extension LibraryStore {
    /// Up to `limit` present assets still waiting for stage 2, with ids above `afterID`, in id order.
    func pendingMetadata(afterID: Int64 = 0, limit: Int) async throws -> [PendingMetadataItem] {
        try await writer.read { db in
            try Row.fetchAll(db, sql: """
            SELECT asset.id, asset.kind, asset.mtime, asset.name, folder.rel_path, root_folder.path
            FROM asset JOIN folder ON folder.id = asset.folder_id JOIN root_folder ON root_folder.id = folder.root_id
            WHERE asset.meta_state = 0 AND asset.state = 0 AND asset.id > ?
            ORDER BY asset.id LIMIT ?
            """, arguments: [afterID, limit]).map { row in
                let directory = LibraryStore.absolutePath(rootPath: row["path"], relativePath: row["rel_path"])
                return PendingMetadataItem(
                    id: row["id"],
                    url: URL(fileURLWithPath: directory + "/" + (row["name"] as String)),
                    kind: MediaKind(rawValue: row["kind"]) ?? .photo,
                    modifiedAt: Date(millisecondsSince1970: row["mtime"])
                )
            }
        }
    }

    /// Saves a batch of stage-2 results in one transaction. Rows whose file changed meanwhile are skipped.
    func saveMetadata(_ updates: [MetadataUpdate]) async throws {
        guard !updates.isEmpty else { return }
        try await writer.write { db in
            let statement = try db.makeStatement(sql: """
            UPDATE asset SET meta_state = ?, width = ?, height = ?, orientation = ?, duration = ?, fps = ?,
              codec = ?, captured_at = ?, quick_hash = ?
            WHERE id = ? AND mtime = ?
            """)
            for update in updates {
                try statement.execute(arguments: [
                    update.state.rawValue, update.width, update.height, update.orientation, update.duration,
                    update.frameRate, update.codec, update.capturedAt?.millisecondsSince1970, update.quickHash,
                    update.id, update.modifiedAt.millisecondsSince1970,
                ])
            }
        }
    }
}
