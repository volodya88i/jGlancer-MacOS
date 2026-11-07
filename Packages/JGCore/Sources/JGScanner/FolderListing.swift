import Foundation
import JGModel
import JGStore

/// Media files directly inside one folder, for viewing a file that was opened from Finder
/// (siblings enumerated shallowly even when the folder is not in the library; docs/FEATURES.md §13).
public enum FolderListing {
    /// Files of `kinds` in `folder`, in natural name order (hidden items, packages and links skipped).
    public static func files(
        in folder: URL, kinds: Set<MediaKind>, lister: DirectoryLister = DirectoryLister()
    ) throws -> [ScannedFile] {
        // Each key is made once, not twice per comparison (a folder of 10 000 files: 10 000 keys, not ~270 000).
        try lister.list(folder, rootID: 0, relativePath: "").files
            .filter { kinds.contains($0.kind) }
            .map { (key: NaturalSortKey.make($0.name), file: $0) }
            .sorted { $0.key < $1.key }
            .map(\.file)
    }
}
