import Foundation
import JGModel
import Testing
@testable import JGStore

/// Files kept only in the cloud (D-124): listed and shown, never read for details until they are downloaded.
struct CloudOnlyTests {
    @Test func cloudFilesWaitForTheirDetailsUntilDownloaded() async throws {
        let store = try LibraryStore.inMemory()
        let root = try await store.addRoot(path: "/lib")
        try await store.scan(root.id, files: [file("here.jpg", inode: 1), file("cloud.jpg", inode: 2, cloudOnly: true)])
        let ids = try await store.idsByName()
        let cloud = try #require(ids["cloud.jpg"])
        #expect(try await store.assets(ids: [cloud]).first?.isCloudOnly == true)
        #expect(try await store.pendingMetadata(limit: 10).map(\.url.lastPathComponent) == ["here.jpg"])
        #expect(try await store.statistics().pendingMetadata == 1)

        // Downloaded (opened in a viewer): same size and date, so only the cloud flag changes, and that is a change.
        let result = try await store.scan(root.id, files: [file("here.jpg", inode: 1), file("cloud.jpg", inode: 2)])
        #expect(result.updated == 1 && result.unchanged == 1)
        #expect(try await store.assets(ids: [cloud]).first?.isCloudOnly == false)
        #expect(try await store.pendingMetadata(limit: 10).map(\.url.lastPathComponent).sorted() == ["cloud.jpg", "here.jpg"])

        // Sent back to the cloud: flagged again; nothing else about it changes.
        _ = try await store.scan(root.id, files: [file("here.jpg", inode: 1), file("cloud.jpg", inode: 2, cloudOnly: true)])
        #expect(try await store.assets(ids: [cloud]).first?.isCloudOnly == true)
        #expect(try await store.assetRefs(for: AssetQuery()).count == 2)
    }

    @Test func aCloudFileIsAddedFlagged() async throws {
        let store = try LibraryStore.inMemory()
        let root = try await store.addRoot(path: "/lib")
        let result = try await store.scan(root.id, files: [file("song.m4a", inode: 9, kind: .audio, cloudOnly: true)])
        #expect(result.added == 1)
        let id = try #require(try await store.idsByName()["song.m4a"])
        #expect(try await store.assets(ids: [id]).first?.isCloudOnly == true)
    }
}
