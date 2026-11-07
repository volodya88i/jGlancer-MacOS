import Foundation
import JGScanner

/// The file-system calls file operations make (docs/ARCHITECTURE.md §12), behind a protocol so safety tests can
/// inject failures, other volumes and a private Trash.
public protocol FileSystem: Sendable {
    func exists(_ url: URL) -> Bool
    /// An identifier of the volume holding `url` (or its folder, if `url` does not exist yet).
    func volume(of url: URL) -> String?
    /// Renames on one volume; fails when `destination` exists.
    func move(_ source: URL, to destination: URL) throws
    /// Copies; fails when `destination` exists.
    func copy(_ source: URL, to destination: URL) throws
    /// Deletes for good. Used only for the operations' own temporary copies and for the source of a move to
    /// another volume after its copy was verified.
    func remove(_ url: URL) throws
    /// Moves to the Trash; returns where the item is now (for a restore).
    func trash(_ url: URL) throws -> URL
    func createDirectory(_ url: URL) throws
    func size(of url: URL) -> Int64?
    func quickHash(of url: URL) -> Data?
    /// Every item below a folder (hidden ones included) as paths relative to it, folders ending in "/", sorted;
    /// nil when `url` is not a folder. Lets a copied folder be checked item by item.
    func itemsBelow(_ url: URL) -> [String]?
}

public extension FileSystem {
    func itemsBelow(_ url: URL) -> [String]? {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory), isDirectory.boolValue,
              let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey])
        else { return nil }
        let base = url.standardizedFileURL.path
        var items: [String] = []
        for case let item as URL in enumerator {
            let path = item.standardizedFileURL.path
            guard path.hasPrefix(base + "/") else { continue }
            let isFolder = (try? item.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            items.append(String(path.dropFirst(base.count + 1)) + (isFolder ? "/" : ""))
        }
        return items.sorted()
    }
}

/// The real file system: `FileManager` and the user's Trash.
public struct LocalFileSystem: FileSystem {
    public init() {}

    public func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    public func volume(of url: URL) -> String? {
        let probe = exists(url) ? url : url.deletingLastPathComponent()
        let values = try? probe.resourceValues(forKeys: [.volumeIdentifierKey])
        return values?.volumeIdentifier.map { String(describing: $0) }
    }

    public func move(_ source: URL, to destination: URL) throws {
        try FileManager.default.moveItem(at: source, to: destination)
    }

    public func copy(_ source: URL, to destination: URL) throws {
        try FileManager.default.copyItem(at: source, to: destination)
    }

    public func remove(_ url: URL) throws {
        try FileManager.default.removeItem(at: url)
    }

    public func trash(_ url: URL) throws -> URL {
        var resulting: NSURL?
        try FileManager.default.trashItem(at: url, resultingItemURL: &resulting)
        guard let trashed = resulting as URL? else { throw CocoaError(.fileNoSuchFile) }
        return trashed
    }

    public func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    public func size(of url: URL) -> Int64? {
        (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init)
    }

    public func quickHash(of url: URL) -> Data? {
        QuickHash.compute(url: url)
    }
}
