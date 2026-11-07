import Foundation
import GRDB
import JGModel

/// Row of `root_folder`.
struct RootRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "root_folder"
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase

    var id: Int64?
    var path: String
    var bookmark: Data?
    var volumeUuid: String?
    var eventDatabaseUuid: String?
    var lastEventId: Int64?
    var isRecursive: Bool
    var isWatched: Bool
    var addedAt: Int64

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var model: RootFolder {
        RootFolder(
            id: id ?? 0, path: path, bookmark: bookmark, volumeUUID: volumeUuid,
            eventDatabaseUUID: eventDatabaseUuid, lastEventID: lastEventId.map { UInt64(bitPattern: $0) },
            isRecursive: isRecursive, isWatched: isWatched, addedAt: Date(millisecondsSince1970: addedAt)
        )
    }
}

/// Row of `folder`.
struct FolderRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "folder"
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase

    var id: Int64?
    var rootId: Int64
    var parentId: Int64?
    var relPath: String
    var name: String
    var state: Int

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    var model: Folder {
        Folder(
            id: id ?? 0, rootID: rootId, parentID: parentId, relativePath: relPath, name: name,
            state: AssetState(rawValue: state) ?? .present
        )
    }
}

/// Row of `asset`.
struct AssetRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "asset"
    static let databaseColumnDecodingStrategy = DatabaseColumnDecodingStrategy.convertFromSnakeCase
    static let databaseColumnEncodingStrategy = DatabaseColumnEncodingStrategy.convertToSnakeCase

    var id: Int64?
    var folderId: Int64
    var name: String
    var nameKey: String
    var kind: Int
    var uti: String?
    var size: Int64
    var mtime: Int64
    var birthTime: Int64?
    var inode: Int64?
    var quickHash: Data?
    var width: Int?
    var height: Int?
    var orientation: Int?
    var duration: Double?
    var fps: Double?
    var codec: String?
    var capturedAt: Int64?
    var rating: Int = 0
    var flag: Int = 0
    var cloudOnly = false
    var state: Int
    var missingSince: Int64?
    var metaState: Int
    var indexedAt: Int64

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }

    /// The model, located in `directory` (absolute path of the asset's folder).
    func model(directory: String) -> Asset {
        Asset(
            id: id ?? 0, folderID: folderId, name: name,
            url: URL(fileURLWithPath: directory).appendingPathComponent(name, isDirectory: false),
            kind: MediaKind(rawValue: kind) ?? .photo,
            typeIdentifier: uti, size: size, modifiedAt: Date(millisecondsSince1970: mtime),
            createdAt: birthTime.map(Date.init(millisecondsSince1970:)), width: width, height: height,
            orientation: orientation, duration: duration, frameRate: fps, codec: codec,
            capturedAt: capturedAt.map(Date.init(millisecondsSince1970:)),
            state: AssetState(rawValue: state) ?? .present,
            metadataState: MetadataState(rawValue: metaState) ?? .pending,
            flag: AssetFlag(rawValue: flag) ?? .none,
            isCloudOnly: cloudOnly
        )
    }

    /// Clears everything stage 2 derives from file content.
    mutating func resetMetadata() {
        quickHash = nil
        width = nil
        height = nil
        orientation = nil
        duration = nil
        fps = nil
        codec = nil
        capturedAt = nil
        metaState = MetadataState.pending.rawValue
    }
}
