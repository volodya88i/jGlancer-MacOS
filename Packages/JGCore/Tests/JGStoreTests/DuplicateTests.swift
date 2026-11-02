import Foundation
import JGModel
import Testing
@testable import JGStore

struct DuplicateTests {
    @Test func groupsBySizeAndQuickHashAndCountsUnread() async throws {
        let store = try LibraryStore.inMemory()
        let root = try await store.addRoot(path: "/lib")
        try await store.scan(root.id, files: [
            file("a.jpg", size: 100, inode: 1), file("b.jpg", size: 100, inode: 2),
            file("c.jpg", size: 100, inode: 3), file("d.jpg", size: 200, inode: 4),
            file("e.jpg", size: 200, inode: 5), file("unread.jpg", size: 100, inode: 6),
        ], subdirectories: ["sub"])
        try await store.scan(root.id, "sub", files: [file("a copy.jpg", size: 100, inode: 7)])
        let ids = try await store.idsByName()
        let same = Data([1, 2, 3])
        let hashes: [String: Data] = ["a.jpg": same, "b.jpg": same, "a copy.jpg": same, "c.jpg": Data([9]), "d.jpg": same, "e.jpg": same]
        try await store.saveMetadata(hashes.compactMap { name, hash in
            ids[name].map { MetadataUpdate(id: $0, modifiedAt: base, state: .extracted, quickHash: hash) }
        })
        let found = try await store.duplicateCandidates()
        let names = found.groups.map { $0.map(\.name).sorted() }
        // Same hash but another size is another group; c has its own hash; unread is not hashed yet.
        #expect(names.count == 2)
        #expect(names.contains(["a copy.jpg", "a.jpg", "b.jpg"]))
        #expect(names.contains(["d.jpg", "e.jpg"]))
        #expect(found.pending == 1)
    }
}
