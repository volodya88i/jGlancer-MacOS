import Foundation
import JGTestSupport
import Testing
@testable import JGActions

struct BatchRenameTests {
    let date = Date(timeIntervalSince1970: 1_720_000_000) // 2024-07-03

    func files(_ names: String..., folder: String = "/f") -> [BatchRenamePattern.File] {
        names.map { BatchRenamePattern.File(url: URL(fileURLWithPath: folder + "/" + $0), date: date) }
    }

    @Test func templatesKeepExtensionsAndPadCounters() {
        let batch = files("IMG_1.jpg", "IMG_2.heic", "clip.mov")
        #expect(BatchRenamePattern(template: "Trip {n}").names(for: batch) == ["Trip 1.jpg", "Trip 2.heic", "Trip 3.mov"])
        #expect(BatchRenamePattern(template: "{date}_{n}", start: 9).names(for: batch)
            == ["2024-07-03_09.jpg", "2024-07-03_10.heic", "2024-07-03_11.mov"])
        #expect(BatchRenamePattern(template: "{name}-{n}", digits: 3).names(for: batch)
            == ["IMG_1-001.jpg", "IMG_2-002.heic", "clip-003.mov"])
        #expect(BatchRenamePattern().names(for: batch) == ["IMG_1.jpg", "IMG_2.heic", "clip.mov"])
    }

    @Test func aNewExtensionReplacesEveryExtensionAndKeepsNames() {
        let batch = files("IMG_1.jpeg", "IMG_2.JPEG", "notes")
        var pattern = BatchRenamePattern()
        pattern.newExtension = " .jpg "
        #expect(pattern.names(for: batch) == ["IMG_1.jpg", "IMG_2.jpg", "notes.jpg"])
        pattern.newExtension = "..."
        #expect(pattern.names(for: batch) == ["IMG_1.jpeg", "IMG_2.JPEG", "notes"])
        pattern.newExtension = "a/b"
        let names = pattern.names(for: batch)
        #expect(BatchRenamePattern.problems(files: batch, names: names) { _ in [] }.allSatisfy { $0 == .invalidCharacters })
    }

    @Test func problemsAreFoundPerFile() {
        let batch = files("a.jpg", "b.jpg", "c.jpg")
        let existing: (URL) -> Set<String> = { _ in ["a.jpg", "b.jpg", "c.jpg", "Taken.jpg"] }
        let problems = BatchRenamePattern.problems(
            files: batch, names: ["  .jpg", "x:y.jpg", "taken.jpg"], existing: existing
        )
        #expect(problems == [.empty, .invalidCharacters, .taken])
        let duplicates = BatchRenamePattern.problems(files: batch, names: ["d.jpg", "D.jpg", "b.jpg"], existing: existing)
        #expect(duplicates == [.duplicate, .duplicate, nil])
        // Trading places with another file of the batch is fine.
        #expect(BatchRenamePattern.problems(files: batch, names: ["b.jpg", "a.jpg", "c.jpg"], existing: existing) == [nil, nil, nil])
    }

    @Test func queueSwapsShiftsAndUndoesInOneRecord() async throws {
        let directory = try TemporaryDirectory()
        let disk = try TestFileSystem(base: directory.url)
        for name in ["1.jpg", "2.jpg", "3.jpg", "other.jpg"] {
            try directory.write("f/\(name)", "content of \(name)")
        }
        let folder = directory.url.appendingPathComponent("f")
        let queue = FileOperationQueue(fileSystem: disk)
        // A shift: 1→2, 2→3, 3→4; and a name that is taken by a file outside the batch fails alone.
        let renamed = await queue.perform(.renameAll([
            (folder.appendingPathComponent("1.jpg"), "2.jpg"),
            (folder.appendingPathComponent("2.jpg"), "3.jpg"),
            (folder.appendingPathComponent("3.jpg"), "other.jpg"),
        ]))
        // 3 cannot become "other", so it keeps its name; then 2 cannot take "3", and 1 cannot take "2".
        #expect(renamed.completed == 0)
        #expect(renamed.failures.count == 3)
        #expect(disk.names(folder).sorted() == ["1.jpg", "2.jpg", "3.jpg", "other.jpg"])
        // Without the blocked one, the shift works.
        let shifted = await queue.perform(.renameAll([
            (folder.appendingPathComponent("1.jpg"), "2.jpg"), (folder.appendingPathComponent("2.jpg"), "4.jpg"),
        ]))
        #expect(shifted.completed == 2)
        #expect(disk.contents(folder.appendingPathComponent("2.jpg")) == "content of 1.jpg")
        #expect(disk.contents(folder.appendingPathComponent("4.jpg")) == "content of 2.jpg")
        #expect(disk.names(folder).filter { $0.hasPrefix(".jglancer") }.isEmpty)
        let undone = await queue.perform(shifted.undo)
        #expect(undone.failures.isEmpty)
        #expect(disk.contents(folder.appendingPathComponent("1.jpg")) == "content of 1.jpg")
        #expect(disk.contents(folder.appendingPathComponent("2.jpg")) == "content of 2.jpg")
        #expect(disk.contents(folder.appendingPathComponent("3.jpg")) == "content of 3.jpg")
        // A swap.
        let swapped = await queue.perform(.renameAll([
            (folder.appendingPathComponent("1.jpg"), "2.jpg"), (folder.appendingPathComponent("2.jpg"), "1.jpg"),
        ]))
        #expect(swapped.completed == 2)
        #expect(disk.contents(folder.appendingPathComponent("1.jpg")) == "content of 2.jpg")
        #expect(disk.names(folder).sorted() == ["1.jpg", "2.jpg", "3.jpg", "other.jpg"])
    }
}
