import Foundation
import JGModel

/// One media file found in a directory listing (stage 1 facts only).
public struct ScannedFile: Hashable, Sendable {
    public let name: String
    public let kind: MediaKind
    public let typeIdentifier: String?
    public let size: Int64
    public let modifiedAt: Date
    public let createdAt: Date?
    /// File identifier (inode) on its volume.
    public let inode: UInt64?

    public init(
        name: String, kind: MediaKind, typeIdentifier: String?, size: Int64,
        modifiedAt: Date, createdAt: Date?, inode: UInt64?
    ) {
        self.name = name
        self.kind = kind
        self.typeIdentifier = typeIdentifier
        self.size = size
        self.modifiedAt = modifiedAt
        self.createdAt = createdAt
        self.inode = inode
    }
}

/// A complete, shallow listing of one directory inside a root, ready to reconcile with the database.
public struct DirectoryScan: Sendable {
    public let rootID: Int64
    /// Path relative to the root, empty for the root itself.
    public let relativePath: String
    /// Media files directly inside the directory.
    public let files: [ScannedFile]
    /// Names of the visible, non-package subdirectories.
    public let subdirectories: [String]
    public let scannedAt: Date

    public init(rootID: Int64, relativePath: String, files: [ScannedFile], subdirectories: [String], scannedAt: Date) {
        self.rootID = rootID
        self.relativePath = relativePath
        self.files = files
        self.subdirectories = subdirectories
        self.scannedAt = scannedAt
    }
}

/// What reconciling one directory changed.
public struct DirectoryScanResult: Equatable, Sendable {
    public var folderID: Int64
    /// New assets.
    public var added = 0
    /// Assets whose content changed (size or modification date); their metadata is re-extracted.
    public var updated = 0
    /// Assets recognized as moved or renamed from elsewhere; they keep their id (albums, edits follow).
    public var moved = 0
    /// Tombstoned assets whose file is back at the same path.
    public var revived = 0
    /// Tombstones created (including in removed subfolders). A file moved elsewhere is first tombstoned
    /// in its old folder and then counted in `moved` where it reappears, possibly in the same scan.
    public var missing = 0
    public var unchanged = 0
    /// Subfolders that vanished.
    public var removedSubfolders = 0

    public init(folderID: Int64) {
        self.folderID = folderID
    }

    /// Whether anything in the database changed.
    public var hasChanges: Bool {
        added + updated + moved + revived + missing + removedSubfolders > 0
    }
}

/// File-system questions the reconciler asks while matching identities (injected so the store does no IO of its own).
public protocol FileProbe: Sendable {
    /// Whether a file exists at `path`.
    func fileExists(atPath path: String) -> Bool
    /// The quick content hash of the file at `path` (see `QuickHash` in JGScanner), or nil if unreadable.
    func quickHash(atPath path: String) -> Data?
}
