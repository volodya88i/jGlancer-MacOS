import Foundation
import Testing
@testable import JGStore

struct IdentityMatcherTests {
    private func candidate(
        _ id: Int64, inode: UInt64? = nil, size: Int64 = 10, modified: Int64 = 1, hash: Data? = nil,
        missing: Bool = true, sameVolume: Bool = true
    ) -> IdentityCandidate {
        IdentityCandidate(
            id: id, inode: inode, size: size, modifiedAt: modified, quickHash: hash,
            isMissing: missing, isSameVolume: sameVolume, path: "/old/\(id)"
        )
    }

    private func match(
        size: Int64 = 10, modified: Int64 = 1, inode: UInt64? = nil, _ candidates: [IdentityCandidate],
        claimed: Set<Int64> = [], probe: FakeProbe = FakeProbe(), hash: Data? = nil
    ) -> Int64? {
        IdentityMatcher.match(
            .init(size: size, modifiedAt: modified, inode: inode),
            candidates: candidates, claimed: claimed, probe: probe, newFileHash: { hash }
        )
    }

    @Test func inodeMatchNeedsSameVolumeAndSize() {
        #expect(match(inode: 4, [candidate(1, inode: 4)]) == 1)
        #expect(match(inode: 4, [candidate(1, inode: 4, sameVolume: false)]) == nil)
        #expect(match(size: 11, inode: 4, [candidate(1, inode: 4)]) == nil)
    }

    @Test func presentCandidateMatchesOnlyIfItsFileIsGone() {
        let present = candidate(1, inode: 4, missing: false)
        #expect(match(inode: 4, [present]) == 1)
        #expect(match(inode: 4, [present], probe: FakeProbe(existingPaths: ["/old/1"])) == nil)
    }

    @Test func contentMatchNeedsSizeDateAndHash() {
        let hash = Data([7])
        #expect(match([candidate(1, hash: hash)], hash: hash) == 1)
        #expect(match(modified: 2, [candidate(1, hash: hash)], hash: hash) == nil)
        #expect(match([candidate(1, hash: hash)], hash: Data([8])) == nil)
        #expect(match([candidate(1, hash: nil)], hash: hash) == nil)
        #expect(match([candidate(1, hash: hash, missing: false)], hash: hash) == nil)
    }

    @Test func claimedAndAmbiguousCandidatesAreSkipped() {
        let hash = Data([7])
        #expect(match([candidate(1, hash: hash)], claimed: [1], hash: hash) == nil)
        #expect(match([candidate(1, hash: hash), candidate(2, hash: hash)], hash: hash) == nil)
    }
}
