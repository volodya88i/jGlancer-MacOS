import Foundation
import JGStore

/// Totals of one scan (stage 1) over one or more directories.
public struct ScanReport: Equatable, Sendable {
    public var directories = 0
    public var added = 0
    public var updated = 0
    public var moved = 0
    public var revived = 0
    public var missing = 0
    public var unchanged = 0
    /// Directories that could not be listed (permissions, races); their rows were left untouched.
    public var unreadableDirectories = 0
    public var duration: TimeInterval = 0

    public init() {}

    /// Whether the scan changed the database.
    public var hasChanges: Bool {
        added + updated + moved + revived + missing > 0
    }

    mutating func add(_ result: DirectoryScanResult) {
        directories += 1
        added += result.added
        updated += result.updated
        moved += result.moved
        revived += result.revived
        missing += result.missing
        unchanged += result.unchanged
    }
}

/// Errors raised by `LibraryScanner`.
public enum ScanError: Error, Equatable, Sendable {
    /// The root folder does not exist or is not a directory (unmounted volume, moved, deleted).
    case rootUnavailable(path: String)
}

/// What a watched root's change batch did.
public struct WatchUpdate: Sendable {
    public let events: [FileSystemEvent]
    public let targets: [RescanTarget]
    public let report: ScanReport
}

/// How far a first scan has come: media files and folders found so far (D-85).
public struct ScanProgress: Equatable, Sendable {
    public var files = 0
    public var folders = 0

    public init(files: Int = 0, folders: Int = 0) {
        self.files = files
        self.folders = folders
    }
}
