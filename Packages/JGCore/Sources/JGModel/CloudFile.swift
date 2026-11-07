import Darwin
import Foundation

/// Files kept only in the cloud: iCloud Drive with Optimize Mac Storage, or another File Provider (Dropbox, OneDrive,
/// Google Drive). Their content is not on this Mac, and reading any of it makes the system download the whole file.
/// The app reads such a file only when the user opens it in a viewer (D-124).
public enum CloudFile {
    /// Whether the file at `path` has no local content (`SF_DATALESS`). Reads metadata only: never downloads.
    public static func isDataless(atPath path: String) -> Bool {
        var info = stat()
        return lstat(path, &info) == 0 && info.st_flags & UInt32(SF_DATALESS) != 0
    }
}
