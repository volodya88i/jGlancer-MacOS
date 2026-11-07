import Foundation
import JGModel
@testable import JGStore

/// A file system made of explicit facts, for identity-matching tests.
struct FakeProbe: FileProbe {
    var existingPaths: Set<String> = []
    var hashes: [String: Data] = [:]

    func fileExists(atPath path: String) -> Bool {
        existingPaths.contains(path)
    }

    func quickHash(atPath path: String) -> Data? {
        hashes[path]
    }
}

let base = Date(timeIntervalSince1970: 1_700_000_000)

func file(
    _ name: String, size: Int64 = 100, modified: TimeInterval = 0, inode: UInt64? = nil, kind: MediaKind = .photo,
    cloudOnly: Bool = false
) -> ScannedFile {
    ScannedFile(
        name: name, kind: kind, typeIdentifier: nil, size: size,
        modifiedAt: base.addingTimeInterval(modified), createdAt: nil, inode: inode, isCloudOnly: cloudOnly
    )
}

extension LibraryStore {
    /// Applies a listing of `relativePath` in root `rootID`.
    @discardableResult
    func scan(
        _ rootID: Int64, _ relativePath: String = "", files: [ScannedFile], subdirectories: [String] = [],
        probe: FakeProbe = FakeProbe()
    ) async throws -> DirectoryScanResult {
        try await applyDirectoryScan(
            DirectoryScan(rootID: rootID, relativePath: relativePath, files: files, subdirectories: subdirectories, scannedAt: base),
            probe: probe
        )
    }

    /// Present asset ids by name across the library.
    func idsByName() async throws -> [String: Int64] {
        let refs = try await assetRefs(for: AssetQuery())
        let assets = try await assets(ids: refs.map(\.id))
        return Dictionary(uniqueKeysWithValues: assets.map { ($0.name, $0.id) })
    }
}
