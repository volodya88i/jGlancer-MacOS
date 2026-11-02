import Foundation

/// A folder the user added to the library. Files inside are indexed in place, never imported.
public struct RootFolder: Hashable, Sendable, Identifiable {
    public let id: Int64
    /// Absolute path with symlinks resolved (FSEvents reports resolved paths).
    public let path: String
    /// Security-scoped bookmark, kept so a sandboxed build is possible later (DECISIONS D-03).
    public let bookmark: Data?
    /// UUID of the volume that holds the folder.
    public let volumeUUID: String?
    /// UUID of the FSEvents database the stored event id belongs to.
    public let eventDatabaseUUID: String?
    /// Last FSEvents event id that has been fully processed; nil before the first watch.
    public let lastEventID: UInt64?
    /// Whether subfolders are indexed.
    public let isRecursive: Bool
    /// Whether the folder is watched for changes.
    public let isWatched: Bool
    public let addedAt: Date

    public init(
        id: Int64, path: String, bookmark: Data?, volumeUUID: String?, eventDatabaseUUID: String?,
        lastEventID: UInt64?, isRecursive: Bool, isWatched: Bool, addedAt: Date
    ) {
        self.id = id
        self.path = path
        self.bookmark = bookmark
        self.volumeUUID = volumeUUID
        self.eventDatabaseUUID = eventDatabaseUUID
        self.lastEventID = lastEventID
        self.isRecursive = isRecursive
        self.isWatched = isWatched
        self.addedAt = addedAt
    }

    /// File URL of the folder.
    public var url: URL {
        URL(fileURLWithPath: path, isDirectory: true)
    }
}
