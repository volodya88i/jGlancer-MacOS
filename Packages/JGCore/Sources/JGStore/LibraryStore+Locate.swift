import Foundation
import GRDB
import JGModel

/// Where a file-system path sits in the library.
public struct LibraryLocation: Equatable, Sendable {
    public let rootID: Int64
    /// The folder row of the path (a directory) or of its parent (a file); nil if not indexed.
    public let folderID: Int64?
    /// The present asset at the path, for files.
    public let assetID: Int64?
}

public extension LibraryStore {
    /// Finds `path` (canonical, absolute) under one of the roots; nil when it is outside the library.
    func location(of path: String, isDirectory: Bool) async throws -> LibraryLocation? {
        let path = Self.normalized(path)
        return try await writer.read { db in
            let roots = try RootRecord.fetchAll(db)
            guard let root = roots.first(where: { path == $0.path || path.hasPrefix($0.path + "/") }),
                  let rootID = root.id
            else { return nil }
            let relative = path == root.path ? "" : String(path.dropFirst(root.path.count + 1))
            let folderPath = isDirectory ? relative : (relative as NSString).deletingLastPathComponent
            let folderID = try Int64.fetchOne(
                db, sql: "SELECT id FROM folder WHERE root_id = ? AND rel_path = ? AND state = 0",
                arguments: [rootID, folderPath]
            )
            var assetID: Int64?
            if !isDirectory, let folderID {
                assetID = try Int64.fetchOne(
                    db, sql: "SELECT id FROM asset WHERE folder_id = ? AND name = ? AND state = 0",
                    arguments: [folderID, (relative as NSString).lastPathComponent]
                )
            }
            return LibraryLocation(rootID: rootID, folderID: folderID, assetID: assetID)
        }
    }
}
