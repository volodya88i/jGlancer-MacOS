import Foundation
import JGScanner
import JGStore

/// Keeps `library.sqlite` in step with the app's file operations: moved files keep their asset id, trashed ones
/// become tombstones and come back with the same id on undo. Copies and new folders are left to the scanner.
public struct LibraryFileIndex: FileIndex {
    private let store: LibraryStore

    public init(store: LibraryStore) {
        self.store = store
    }

    public func moved(from source: URL, to destination: URL) async {
        _ = try? await store.moveAsset(from: CanonicalPath.of(source), to: Self.canonical(destination))
    }

    public func removed(_ url: URL) async {
        try? await store.markMissing(at: Self.canonical(url))
    }

    public func restored(_ url: URL) async {
        _ = try? await store.revive(at: CanonicalPath.of(url))
    }

    /// The canonical path of a file that may no longer exist (its folder still does).
    private static func canonical(_ url: URL) -> String {
        CanonicalPath.of(url.deletingLastPathComponent()) + "/" + url.lastPathComponent
    }
}
