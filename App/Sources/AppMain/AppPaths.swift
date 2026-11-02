import Foundation

/// Where the app keeps its data.
///
/// The launch argument `-JGDataDirectory <path>` redirects the library database and the thumbnail
/// cache, so benchmarks never touch the user's real library.
enum AppPaths {
    /// Data directory override from the launch arguments, if any.
    static var dataOverride: URL? {
        UserDefaults.standard.string(forKey: "JGDataDirectory").map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    /// `~/Library/Application Support/<name>/library.sqlite`
    static var libraryDatabase: URL {
        (dataOverride ?? URL.applicationSupportDirectory.appendingPathComponent(AppIdentity.supportDirectoryName, isDirectory: true))
            .appendingPathComponent("library.sqlite")
    }

    /// The daily copy of the library, next to it (`LibraryStore.backup`).
    static var libraryBackup: URL {
        libraryDatabase.deletingLastPathComponent().appendingPathComponent("library-backup.sqlite")
    }

    /// Segments opened in another app (Edit In, D-74): kept, so edits saved in place are never lost.
    /// `~/Library/Application Support/<name>/Edited Segments`
    static var editedSegments: URL {
        libraryDatabase.deletingLastPathComponent().appendingPathComponent("Edited Segments", isDirectory: true)
    }

    /// The stem splitter's models (D-97): `~/Library/Application Support/<name>/Models`.
    static var stemModels: URL {
        libraryDatabase.deletingLastPathComponent().appendingPathComponent("Models", isDirectory: true)
    }

    /// `~/Library/Caches/<bundle id>/cache.sqlite`
    static var thumbnailCache: URL {
        (dataOverride ?? URL.cachesDirectory.appendingPathComponent(AppIdentity.cachesDirectoryName, isDirectory: true))
            .appendingPathComponent("cache.sqlite")
    }
}
