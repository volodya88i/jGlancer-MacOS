import Foundation
import GRDB

/// The library database (`library.sqlite`): roots, folders and assets (docs/ARCHITECTURE.md §4).
///
/// GRDB already serializes writes and runs reads concurrently, so the store is a `Sendable`
/// class rather than an actor (DECISIONS D-29). Every public method is `async`: callers on the
/// main actor never block on the database.
public final class LibraryStore: Sendable {
    let writer: any DatabaseWriter

    /// Opens (creating if needed) the database at `url` in WAL mode and migrates it.
    public static func open(at url: URL) throws -> LibraryStore {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return try LibraryStore(writer: DatabasePool(path: url.path, configuration: configuration))
    }

    /// An in-memory database, for tests and previews.
    public static func inMemory() throws -> LibraryStore {
        try LibraryStore(writer: DatabaseQueue(configuration: configuration))
    }

    private static var configuration: Configuration {
        var configuration = Configuration()
        configuration.label = "library"
        return configuration
    }

    init(writer: any DatabaseWriter) throws {
        self.writer = writer
        try LibrarySchema.migrator.migrate(writer)
    }

    /// Names of the applied migrations, oldest first.
    public func appliedMigrations() async throws -> [String] {
        try await writer.read { db in try LibrarySchema.migrator.appliedMigrations(db) }
    }
}
