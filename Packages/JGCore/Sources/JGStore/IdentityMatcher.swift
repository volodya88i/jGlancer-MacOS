import Foundation

/// An existing asset that a newly found file might be (docs/ARCHITECTURE.md §13).
struct IdentityCandidate: Equatable {
    let id: Int64
    let inode: UInt64?
    let size: Int64
    let modifiedAt: Int64
    let quickHash: Data?
    let isMissing: Bool
    /// Whether the candidate's root is on the same volume as the new file (inodes are per volume).
    let isSameVolume: Bool
    let path: String
}

/// Decides whether a new file is an existing asset that was moved or renamed outside the app.
///
/// Rules, best effort:
/// 1. Same volume and inode, same size, and the candidate's old path no longer exists (or is a tombstone).
/// 2. Otherwise a tombstone with equal size, modification date and quick hash, if exactly one matches
///    (covers copies across volumes, which change the inode).
/// Anything else is a new asset; the old row stays a tombstone.
enum IdentityMatcher {
    /// Stage-1 facts of the newly found file.
    struct NewFile {
        let size: Int64
        let modifiedAt: Int64
        let inode: UInt64?
    }

    static func match(
        _ file: NewFile,
        candidates: [IdentityCandidate],
        claimed: Set<Int64>,
        probe: any FileProbe,
        newFileHash: () -> Data?
    ) -> Int64? {
        let open = candidates.filter { !claimed.contains($0.id) }
        let size = file.size
        if let inode = file.inode {
            let byInode = open.filter { $0.isSameVolume && $0.inode == inode && $0.size == size }
            if let hit = byInode.first(where: { $0.isMissing || !probe.fileExists(atPath: $0.path) }) {
                return hit.id
            }
        }
        let byContent = open.filter {
            $0.isMissing && $0.size == size && $0.modifiedAt == file.modifiedAt && $0.quickHash != nil
        }
        guard !byContent.isEmpty, let hash = newFileHash() else { return nil }
        let hits = byContent.filter { $0.quickHash == hash }
        return hits.count == 1 ? hits[0].id : nil
    }
}
