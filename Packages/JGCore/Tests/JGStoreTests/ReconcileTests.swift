import Foundation
import JGModel
import Testing
@testable import JGStore

/// Diff cases (PLAN Phase 1): add, unchanged, modify, remove, revive, rename, move, folder removal.
struct ReconcileTests {
    @Test func firstScanAddsAndSecondScanChangesNothing() async throws {
        let store = try LibraryStore.inMemory()
        let root = try await store.addRoot(path: "/lib")
        let files = [file("a.jpg", inode: 1), file("b.mov", inode: 2, kind: .video)]
        let first = try await store.scan(root.id, files: files)
        #expect(first.added == 2)
        let second = try await store.scan(root.id, files: files)
        #expect(second.unchanged == 2)
        #expect(!second.hasChanges)
    }

    @Test func modifiedFileIsUpdatedAndQueuedForMetadataAgain() async throws {
        let store = try LibraryStore.inMemory()
        let root = try await store.addRoot(path: "/lib")
        try await store.scan(root.id, files: [file("a.jpg", size: 100, inode: 1)])
        let id = try #require(try await store.idsByName()["a.jpg"])
        try await store.saveMetadata([MetadataUpdate(id: id, modifiedAt: base, state: .extracted, width: 10, height: 20)])
        let result = try await store.scan(root.id, files: [file("a.jpg", size: 200, modified: 60, inode: 1)])
        #expect(result.updated == 1)
        let asset = try #require(try await store.assets(ids: [id]).first)
        #expect(asset.size == 200)
        #expect(asset.width == nil)
        #expect(asset.metadataState == .pending)
    }

    @Test func removedFileBecomesATombstoneAndRevivesWithTheSameID() async throws {
        let store = try LibraryStore.inMemory()
        let root = try await store.addRoot(path: "/lib")
        try await store.scan(root.id, files: [file("a.jpg", inode: 1), file("b.jpg", inode: 2)])
        let id = try #require(try await store.idsByName()["a.jpg"])
        let removal = try await store.scan(root.id, files: [file("b.jpg", inode: 2)])
        #expect(removal.missing == 1)
        #expect(try await store.idsByName()["a.jpg"] == nil)
        #expect(try await store.statistics().missingAssets == 1)
        let back = try await store.scan(root.id, files: [file("a.jpg", inode: 1), file("b.jpg", inode: 2)])
        #expect(back.revived == 1)
        #expect(try await store.idsByName()["a.jpg"] == id)
    }

    @Test func renameInTheSameFolderKeepsTheID() async throws {
        let store = try LibraryStore.inMemory()
        let root = try await store.addRoot(path: "/lib")
        try await store.scan(root.id, files: [file("old.jpg", inode: 7)])
        let id = try #require(try await store.idsByName()["old.jpg"])
        let result = try await store.scan(root.id, files: [file("new.jpg", inode: 7)])
        #expect(result.moved == 1)
        #expect(result.added == 0)
        #expect(try await store.idsByName() == ["new.jpg": id])
    }

    @Test func moveToAnotherFolderKeepsTheIDWhenTheOldFolderIsScannedFirst() async throws {
        let store = try LibraryStore.inMemory()
        let root = try await store.addRoot(path: "/lib")
        try await store.scan(root.id, files: [file("x.jpg", inode: 9)], subdirectories: ["sub"])
        let id = try #require(try await store.idsByName()["x.jpg"])
        try await store.scan(root.id, files: [], subdirectories: ["sub"])
        let moved = try await store.scan(root.id, "sub", files: [file("x.jpg", inode: 9)])
        #expect(moved.moved == 1)
        let asset = try #require(try await store.assets(ids: [id]).first)
        #expect(asset.state == .present)
        #expect(try await store.fileURL(assetID: id)?.path == "/lib/sub/x.jpg")
    }

    @Test func moveToAnotherFolderKeepsTheIDWhenTheNewFolderIsScannedFirst() async throws {
        let store = try LibraryStore.inMemory()
        let root = try await store.addRoot(path: "/lib")
        try await store.scan(root.id, files: [file("x.jpg", inode: 9)], subdirectories: ["sub"])
        let id = try #require(try await store.idsByName()["x.jpg"])
        // The old path no longer exists (FakeProbe knows no paths), so the inode match is a move.
        let moved = try await store.scan(root.id, "sub", files: [file("x.jpg", inode: 9)])
        #expect(moved.moved == 1)
        let rescanOld = try await store.scan(root.id, files: [], subdirectories: ["sub"])
        #expect(rescanOld.missing == 0)
        #expect(try await store.fileURL(assetID: id)?.path == "/lib/sub/x.jpg")
    }

    @Test func hardLinkWithTheSameInodeIsNotAMove() async throws {
        let store = try LibraryStore.inMemory()
        let root = try await store.addRoot(path: "/lib")
        try await store.scan(root.id, files: [file("x.jpg", inode: 9)], subdirectories: ["sub"])
        let probe = FakeProbe(existingPaths: ["/lib/x.jpg"])
        let result = try await store.scan(root.id, "sub", files: [file("link.jpg", inode: 9)], probe: probe)
        #expect(result.added == 1)
        #expect(result.moved == 0)
    }

    @Test func copyAcrossVolumesIsMatchedByQuickHash() async throws {
        let store = try LibraryStore.inMemory()
        let source = try await store.addRoot(path: "/Volumes/A/lib", volumeUUID: "A")
        let target = try await store.addRoot(path: "/Volumes/B/lib", volumeUUID: "B")
        try await store.scan(source.id, files: [file("x.jpg", size: 500, inode: 5)])
        let id = try #require(try await store.idsByName()["x.jpg"])
        let hash = Data([1, 2, 3])
        try await store.saveMetadata([MetadataUpdate(id: id, modifiedAt: base, state: .extracted, quickHash: hash)])
        try await store.scan(source.id, files: [])
        let probe = FakeProbe(hashes: ["/Volumes/B/lib/x.jpg": hash])
        let result = try await store.scan(target.id, files: [file("x.jpg", size: 500, inode: 5)], probe: probe)
        #expect(result.moved == 1)
        #expect(try await store.fileURL(assetID: id)?.path == "/Volumes/B/lib/x.jpg")
    }

    @Test func sameInodeOnAnotherVolumeIsNotAMatch() async throws {
        let store = try LibraryStore.inMemory()
        let source = try await store.addRoot(path: "/Volumes/A/lib", volumeUUID: "A")
        let target = try await store.addRoot(path: "/Volumes/B/lib", volumeUUID: "B")
        try await store.scan(source.id, files: [file("x.jpg", inode: 5)])
        try await store.scan(source.id, files: [])
        let result = try await store.scan(target.id, files: [file("other.jpg", inode: 5)])
        #expect(result.added == 1)
    }

    @Test func ambiguousContentMatchesCreateNewAssets() async throws {
        let store = try LibraryStore.inMemory()
        let root = try await store.addRoot(path: "/lib")
        try await store.scan(root.id, files: [file("a.jpg", size: 10, inode: 1), file("b.jpg", size: 10, inode: 2)])
        let ids = try await store.idsByName()
        let hash = Data([9])
        try await store.saveMetadata(ids.values.map { MetadataUpdate(id: $0, modifiedAt: base, state: .extracted, quickHash: hash) })
        try await store.scan(root.id, files: [])
        let probe = FakeProbe(hashes: ["/lib/c.jpg": hash])
        let result = try await store.scan(root.id, files: [file("c.jpg", size: 10, inode: 3)], probe: probe)
        #expect(result.added == 1)
        #expect(result.moved == 0)
    }

    @Test func removedSubfolderTombstonesItsSubtreeAndComesBack() async throws {
        let store = try LibraryStore.inMemory()
        let root = try await store.addRoot(path: "/lib")
        try await store.scan(root.id, files: [], subdirectories: ["2024"])
        try await store.scan(root.id, "2024", files: [file("a.jpg", inode: 1)], subdirectories: ["May"])
        try await store.scan(root.id, "2024/May", files: [file("b.jpg", inode: 2)])
        #expect(try await store.folders(rootID: root.id).map(\.relativePath) == ["", "2024", "2024/May"])
        let removal = try await store.scan(root.id, files: [])
        #expect(removal.removedSubfolders == 1)
        #expect(removal.missing == 2)
        #expect(try await store.folders(rootID: root.id).map(\.relativePath) == [""])
        try await store.scan(root.id, files: [], subdirectories: ["2024"])
        let back = try await store.scan(root.id, "2024", files: [file("a.jpg", inode: 1)], subdirectories: [])
        #expect(back.revived == 1)
        #expect(try await store.folders(rootID: root.id).map(\.relativePath) == ["", "2024"])
    }
}
