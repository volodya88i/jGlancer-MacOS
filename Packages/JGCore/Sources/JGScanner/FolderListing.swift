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
        try lister.list(folder, rootID: 0, relativePath: "").files
            .filter { kinds.contains($0.kind) }
            .sorted { NaturalSortKey.make($0.name) < NaturalSortKey.make($1.name) }
    }
}
