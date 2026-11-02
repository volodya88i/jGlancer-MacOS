import Foundation
import JGModel
import JGScanner
import JGStore
import JGTestSupport
import Testing
@testable import JGActions

/// The real file system inside a temporary folder, with a private Trash, a simulated second volume and
/// injected failures (docs/ARCHITECTURE.md §20: mandatory data-safety tests).
final class TestFileSystem: FileSystem, @unchecked Sendable {
    let base: URL
    let trashFolder: URL
    /// Paths under this folder are on "another volume".
    let otherVolume: URL
    private let lock = NSLock()
    private var moves = 0
    var failMoveNumber: Int?
    var corruptCopies = false
    /// Deleting anything under this folder fails (a source that cannot be removed).
    var failRemoveUnder: URL?

    init(base: URL) throws {
        self.base = base
        trashFolder = base.appendingPathComponent(".Trash", isDirectory: true)
        otherVolume = base.appendingPathComponent("volumeB", isDirectory: true)
        try FileManager.default.createDirectory(at: trashFolder, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: otherVolume, withIntermediateDirectories: true)
    }

    func exists(_ url: URL) -> Bool {
        FileManager.default.fileExists(atPath: url.path)
    }

    func volume(of url: URL) -> String? {
        url.path.hasPrefix(otherVolume.path) ? "B" : "A"
    }

    func move(_ source: URL, to destination: URL) throws {
        let number = lock.withLock {
            moves += 1
            return moves
        }
        if number == failMoveNumber {
            throw CocoaError(.fileWriteUnknown)
        }
        try FileManager.default.moveItem(at: source, to: destination)
    }

    func copy(_ source: URL, to destination: URL) throws {
        try FileManager.default.copyItem(at: source, to: destination)
        if corruptCopies {
            let handle = try FileHandle(forWritingTo: destination)
            try handle.seekToEnd()
            try handle.write(contentsOf: Data([0]))
            try handle.close()
        }
    }

    func remove(_ url: URL) throws {
        if let folder = failRemoveUnder, url.path.hasPrefix(folder.path) {
            throw CocoaError(.fileWriteNoPermission)
        }
        try FileManager.default.removeItem(at: url)
    }

    func trash(_ url: URL) throws -> URL {
        let target = trashFolder.appendingPathComponent(UUID().uuidString + "-" + url.lastPathComponent)
        try FileManager.default.moveItem(at: url, to: target)
        return target
    }

    func createDirectory(_ url: URL) throws {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: false)
    }

    func size(of url: URL) -> Int64? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.size] as? NSNumber)?.int64Value
    }

    func quickHash(of url: URL) -> Data? {
        try? Data(contentsOf: url)
    }

    /// File names in `folder`, temporary and hidden ones included, sorted.
    func names(_ folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? []).sorted()
    }

    func contents(_ url: URL) -> String? {
        (try? Data(contentsOf: url)).flatMap { String(data: $0, encoding: .utf8) }
    }
}

struct FileOperationSafetyTests {
    let directory: TemporaryDirectory
    let disk: TestFileSystem
    let source: URL
    let destination: URL

    init() throws {
        directory = try TemporaryDirectory()
        disk = try TestFileSystem(base: directory.url)
        source = directory.url.appendingPathComponent("src", isDirectory: true)
        destination = directory.url.appendingPathComponent("dst", isDirectory: true)
        for name in ["a.jpg", "b.jpg", "c.jpg"] {
            try directory.write("src/\(name)", "content of \(name)")
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
    }

    func files(_ names: String...) -> [URL] {
        names.map { source.appendingPathComponent($0) }
    }

    @Test func moveThenUndoThenRedo() async {
        let queue = FileOperationQueue(fileSystem: disk)
        let moved = await queue.perform(.move(files("a.jpg", "b.jpg"), to: destination))
        #expect(moved.completed == 2)
        #expect(disk.names(destination) == ["a.jpg", "b.jpg"])
        #expect(disk.names(source) == ["c.jpg"])
        let undone = await queue.perform(moved.undo)
        #expect(undone.failures.isEmpty)
        #expect(disk.names(source) == ["a.jpg", "b.jpg", "c.jpg"])
        #expect(disk.names(destination).isEmpty)
        _ = await queue.perform(undone.undo)
        #expect(disk.names(destination) == ["a.jpg", "b.jpg"])
        #expect(disk.contents(destination.appendingPathComponent("a.jpg")) == "content of a.jpg")
    }

    @Test func aFailureMidBatchKeepsEveryFileAndUndoesTheRest() async {
        disk.failMoveNumber = 2
        let queue = FileOperationQueue(fileSystem: disk)
        let result = await queue.perform(.move(files("a.jpg", "b.jpg", "c.jpg"), to: destination))
        #expect(result.completed == 2)
        #expect(result.failures == files("b.jpg"))
        #expect(disk.names(source) == ["b.jpg"])
        #expect(disk.names(destination) == ["a.jpg", "c.jpg"])
        disk.failMoveNumber = nil
        _ = await queue.perform(result.undo)
        #expect(disk.names(source) == ["a.jpg", "b.jpg", "c.jpg"])
        #expect(disk.names(destination).isEmpty)
    }

    @Test func aMoveToAnotherVolumeVerifiesBeforeDeletingTheSource() async {
        let queue = FileOperationQueue(fileSystem: disk)
        let result = await queue.perform(.move(files("a.jpg"), to: disk.otherVolume))
        #expect(result.completed == 1)
        #expect(disk.names(disk.otherVolume) == ["a.jpg"])
        #expect(disk.names(source) == ["b.jpg", "c.jpg"])
        _ = await queue.perform(result.undo)
        #expect(disk.contents(source.appendingPathComponent("a.jpg")) == "content of a.jpg")
        #expect(disk.names(disk.otherVolume).isEmpty)
    }

    @Test func aBadCopyNeverCostsTheOriginal() async {
        disk.corruptCopies = true
        let queue = FileOperationQueue(fileSystem: disk)
        let moved = await queue.perform(.move(files("a.jpg"), to: disk.otherVolume))
        #expect(moved.failures == files("a.jpg"))
        let copied = await queue.perform(.copy(files("b.jpg"), to: destination))
        #expect(copied.failures == files("b.jpg"))
        #expect(disk.names(source) == ["a.jpg", "b.jpg", "c.jpg"])
        #expect(disk.names(disk.otherVolume).isEmpty)
        #expect(disk.names(destination).isEmpty)
        #expect(disk.contents(source.appendingPathComponent("a.jpg")) == "content of a.jpg")
    }

    @Test func whenTheSourceCannotBeDeletedTheMoveIsTakenBack() async {
        disk.failRemoveUnder = source
        let queue = FileOperationQueue(fileSystem: disk)
        let result = await queue.perform(.move(files("a.jpg"), to: disk.otherVolume))
        #expect(result.failures == files("a.jpg"))
        #expect(disk.names(source) == ["a.jpg", "b.jpg", "c.jpg"])
        #expect(disk.names(disk.otherVolume).isEmpty)
    }

    @Test func nameCollisionsFollowThePolicy() async throws {
        try directory.write("dst/a.jpg", "old a")
        try directory.write("dst/a 2.jpg", "old a 2")
        let queue = FileOperationQueue(fileSystem: disk)
        let skipped = await queue.perform(.copy(files("a.jpg"), to: destination), conflicts: .skip)
        #expect(skipped.skipped == files("a.jpg"))
        let both = await queue.perform(.copy(files("a.jpg"), to: destination), conflicts: .keepBoth)
        #expect(both.results.map(\.lastPathComponent) == ["a 3.jpg"])
        let replaced = await queue.perform(.move(files("a.jpg"), to: destination), conflicts: .replace)
        #expect(replaced.completed == 1)
        #expect(disk.contents(destination.appendingPathComponent("a.jpg")) == "content of a.jpg")
        #expect(disk.names(disk.trashFolder).count == 1)
        // Undo brings the moved file back and the replaced one out of the Trash.
        _ = await queue.perform(replaced.undo)
        #expect(disk.contents(source.appendingPathComponent("a.jpg")) == "content of a.jpg")
        #expect(disk.contents(destination.appendingPathComponent("a.jpg")) == "old a")
        #expect(disk.names(disk.trashFolder).isEmpty)
    }

    @Test func trashRoundTripAndAnOccupiedPlace() async throws {
        let queue = FileOperationQueue(fileSystem: disk)
        let trashed = await queue.perform(.trash(files("a.jpg", "b.jpg")))
        #expect(trashed.completed == 2)
        #expect(disk.names(source) == ["c.jpg"])
        try directory.write("src/b.jpg", "a new b")
        _ = await queue.perform(trashed.undo)
        #expect(disk.names(source) == ["a.jpg", "b 2.jpg", "b.jpg", "c.jpg"])
        #expect(disk.contents(source.appendingPathComponent("b 2.jpg")) == "content of b.jpg")
        #expect(disk.names(disk.trashFolder).isEmpty)
    }

    @Test func renameRulesAndUndo() async {
        let queue = FileOperationQueue(fileSystem: disk)
        #expect(await queue.perform(.rename(files("a.jpg")[0], to: "b.jpg")).failures.count == 1)
        #expect(await queue.perform(.rename(files("a.jpg")[0], to: "x/y.jpg")).failures.count == 1)
        #expect(await queue.perform(.rename(files("a.jpg")[0], to: "  ")).failures.count == 1)
        let renamed = await queue.perform(.rename(files("a.jpg")[0], to: "Holiday.jpg"))
        #expect(disk.names(source) == ["Holiday.jpg", "b.jpg", "c.jpg"])
        let caseOnly = await queue.perform(.rename(files("b.jpg")[0], to: "B.jpg"))
        #expect(caseOnly.completed == 1)
        _ = await queue.perform(renamed.undo)
        #expect(disk.names(source).contains("a.jpg"))
    }

    @Test func copyUndoTrashesOnlyTheCopiesAndLeavesNoTemporaryFiles() async {
        let queue = FileOperationQueue(fileSystem: disk)
        let copied = await queue.perform(.copy(files("a.jpg", "b.jpg"), to: destination))
        #expect(disk.names(destination) == ["a.jpg", "b.jpg"])
        _ = await queue.perform(copied.undo)
        #expect(disk.names(destination).isEmpty)
        #expect(disk.names(source) == ["a.jpg", "b.jpg", "c.jpg"])
        #expect(disk.names(disk.trashFolder).count == 2)
    }

    @Test func cancellingStopsBetweenItems() async {
        let queue = FileOperationQueue(fileSystem: disk)
        let result = await queue.perform(.move(files("a.jpg", "b.jpg", "c.jpg"), to: destination)) { progress in
            if progress.done == 1 {
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        #expect(result.wasCancelled)
        #expect(result.completed == 1)
        #expect(disk.names(destination) == ["a.jpg"])
        #expect(disk.names(source) == ["b.jpg", "c.jpg"])
    }

    @Test func newFolderGetsAFreeNameAndUndoTrashesIt() async throws {
        try FileManager.default.createDirectory(
            at: destination.appendingPathComponent("untitled folder"),
            withIntermediateDirectories: false
        )
        let queue = FileOperationQueue(fileSystem: disk)
        let created = await queue.perform(.createFolder(inside: destination, name: "untitled folder"))
        #expect(created.results.map(\.lastPathComponent) == ["untitled folder 2"])
        _ = await queue.perform(created.undo)
        #expect(disk.names(destination) == ["untitled folder"])
    }
}

struct LibraryFileIndexTests {
    @Test func movedTrashedAndRestoredFilesKeepTheirAssetIDs() async throws {
        let directory = try TemporaryDirectory()
        let photo = try directory.write("lib/a.jpg", "photo")
        try FileManager.default.createDirectory(at: directory.url.appendingPathComponent("lib/sub"), withIntermediateDirectories: true)
        let store = try LibraryStore.inMemory()
        let root = try await store.addRoot(path: directory.url.appendingPathComponent("lib").path)
        _ = try await store.applyDirectoryScan(
            DirectoryScan(rootID: root.id, relativePath: "", files: [
                ScannedFile(name: "a.jpg", kind: .photo, typeIdentifier: nil, size: 5, modifiedAt: Date(), createdAt: nil, inode: nil),
            ], subdirectories: ["sub"], scannedAt: Date()),
            probe: DiskFileProbe()
        )
        let id = try #require(try await store.location(of: photo.path, isDirectory: false)?.assetID)
        let disk = try TestFileSystem(base: directory.url)
        let queue = FileOperationQueue(fileSystem: disk, index: LibraryFileIndex(store: store))
        let sub = directory.url.appendingPathComponent("lib/sub", isDirectory: true)
        let moved = await queue.perform(.move([photo], to: sub))
        let movedPath = sub.appendingPathComponent("a.jpg").path
        #expect(try await store.location(of: movedPath, isDirectory: false)?.assetID == id)
        let trashed = await queue.perform(.trash(moved.results))
        #expect(try await store.location(of: movedPath, isDirectory: false)?.assetID == nil)
        _ = await queue.perform(trashed.undo)
        #expect(try await store.location(of: movedPath, isDirectory: false)?.assetID == id)
    }
}
