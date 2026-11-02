import Foundation
import JGModel
import JGStore
import JGTestSupport
import Testing
@testable import JGScanner

/// End-to-end scans of real temporary folders (PLAN Phase 1 diff cases on disk).
struct ScannerTests {
    /// A scanned temporary library: a.jpg, b.mov, 2024/c.jpg, 2024/May/d.m4a and a non-media file.
    private struct Fixture {
        let folder: TemporaryDirectory
        let scanner: LibraryScanner
        let root: RootFolder
    }

    private func setUp() async throws -> Fixture {
        let folder = try TemporaryDirectory()
        try folder.write("a.jpg")
        try folder.write("b.mov")
        try folder.write("2024/c.jpg")
        try folder.write("2024/May/d.m4a")
        try folder.write("notes.txt")
        let scanner = try LibraryScanner(store: LibraryStore.inMemory())
        let (root, report) = try await scanner.addRoot(at: folder.url)
        #expect(report.added == 4)
        #expect(report.directories == 3)
        return Fixture(folder: folder, scanner: scanner, root: root)
    }

    private func ids(_ scanner: LibraryScanner) async throws -> [String: Int64] {
        let store = scanner.store
        let refs = try await store.assetRefs(for: AssetQuery())
        return try await Dictionary(uniqueKeysWithValues: store.assets(ids: refs.map(\.id)).map { ($0.name, $0.id) })
    }

    @Test func addingARootIndexesItsTree() async throws {
        let fixture = try await setUp()
        let (scanner, root) = (fixture.scanner, fixture.root)
        let folders = try await scanner.store.folders(rootID: root.id).map(\.relativePath)
        #expect(folders == ["", "2024", "2024/May"])
        #expect(try await ids(scanner).keys.sorted() == ["a.jpg", "b.mov", "c.jpg", "d.m4a"])
        let again = try await scanner.scan(rootID: root.id)
        #expect(!again.hasChanges)
    }

    @Test func renamesAndMovesOnDiskKeepAssetIDs() async throws {
        let fixture = try await setUp()
        let (folder, scanner, root) = (fixture.folder, fixture.scanner, fixture.root)
        let before = try await ids(scanner)
        try folder.move("a.jpg", to: "renamed.jpg")
        try folder.move("2024/c.jpg", to: "2024/May/c.jpg")
        try folder.move("b.mov", to: "Elsewhere/b.mov")
        let report = try await scanner.scan(rootID: root.id)
        #expect(report.moved == 3)
        #expect(report.added == 0)
        #expect(try await scanner.store.statistics().missingAssets == 0)
        let after = try await ids(scanner)
        #expect(after["renamed.jpg"] == before["a.jpg"])
        #expect(after["c.jpg"] == before["c.jpg"])
        #expect(after["b.mov"] == before["b.mov"])
        let path = try await scanner.store.fileURL(assetID: #require(after["c.jpg"]))?.path
        #expect(path == folder.url.appendingPathComponent("2024/May/c.jpg").path)
    }

    @Test func modificationsDeletionsAndRemovedFolders() async throws {
        let fixture = try await setUp()
        let (folder, scanner, root) = (fixture.folder, fixture.scanner, fixture.root)
        try folder.write("a.jpg", "longer content")
        try folder.remove("b.mov")
        try folder.remove("2024")
        let report = try await scanner.scan(rootID: root.id)
        #expect(report.updated == 1)
        #expect(report.missing == 3)
        #expect(try await ids(scanner).keys.sorted() == ["a.jpg"])
        #expect(try await scanner.store.folders(rootID: root.id).map(\.relativePath) == [""])
        #expect(try await scanner.store.statistics().missingAssets == 3)
    }

    @Test func canonicalPathKeepsPrivatePrefix() throws {
        let folder = try TemporaryDirectory()
        #expect(CanonicalPath.of(URL(fileURLWithPath: "/var")) == "/private/var")
        #expect(CanonicalPath.of(folder.url) == folder.url.path)
    }

    @Test func missingRootIsReportedWithoutTouchingRows() async throws {
        let fixture = try await setUp()
        let (folder, scanner, root) = (fixture.folder, fixture.scanner, fixture.root)
        let path = folder.url.path
        try FileManager.default.removeItem(at: folder.url)
        await #expect(throws: ScanError.rootUnavailable(path: path)) {
            try await scanner.scan(rootID: root.id)
        }
        #expect(try await scanner.store.statistics().presentAssets == 4)
    }

    @Test func metadataIsExtractedFromRealMedia() async throws {
        let folder = try TemporaryDirectory()
        try MediaFactory.jpeg(
            at: folder.url.appendingPathComponent("portrait.jpg"), width: 64, height: 48, orientation: 6,
            captured: "2024:05:17 10:30:00"
        )
        try MediaFactory.wav(at: folder.url.appendingPathComponent("tone.wav"), seconds: 1.5)
        try await MediaFactory.mov(at: folder.url.appendingPathComponent("clip.mov"), width: 64, height: 32, frames: 30, fps: 30)
        try folder.write("broken.jpg", "not an image")
        let scanner = try LibraryScanner(store: LibraryStore.inMemory())
        _ = try await scanner.addRoot(at: folder.url)
        #expect(try await scanner.extractMetadata() == 4)
        let store = scanner.store
        let assets = try await store.assets(ids: store.assetRefs(for: AssetQuery()).map(\.id))
        let byName = Dictionary(uniqueKeysWithValues: assets.map { ($0.name, $0) })

        let photo = try #require(byName["portrait.jpg"])
        #expect(photo.metadataState == .extracted)
        #expect(photo.width == 48 && photo.height == 64)
        #expect(photo.orientation == 6)
        #expect(photo.capturedAt == Date(timeIntervalSince1970: 1_715_934_600)) // 2024-05-17 08:30 UTC

        let audio = try #require(byName["tone.wav"])
        #expect(abs((audio.duration ?? 0) - 1.5) < 0.01)
        #expect(audio.codec == "lpcm")

        let video = try #require(byName["clip.mov"])
        #expect(video.width == 64 && video.height == 32)
        #expect(abs((video.duration ?? 0) - 1) < 0.05)
        #expect(abs((video.frameRate ?? 0) - 30) < 0.5)
        #expect(video.codec == "avc1")

        #expect(byName["broken.jpg"]?.metadataState == .failed)
        #expect(try await store.statistics().pendingMetadata == 0)
    }

    @Test func quickHashSeesHeadTailAndSize() throws {
        let folder = try TemporaryDirectory()
        let big = String(repeating: "a", count: 300_000)
        let first = try folder.write("1.bin", big)
        let same = try folder.write("2.bin", big)
        let otherTail = try folder.write("3.bin", String(big.dropLast()) + "b")
        let otherMiddle = try folder.write("4.bin", String(big.prefix(150_000)) + "b" + String(big.suffix(149_999)))
        let small = try folder.write("5.bin", "hello")
        #expect(QuickHash.compute(url: first) == QuickHash.compute(url: same))
        #expect(QuickHash.compute(url: first) != QuickHash.compute(url: otherTail))
        // The middle is not sampled: identical head, tail and size hash the same (documented limitation).
        #expect(QuickHash.compute(url: first) == QuickHash.compute(url: otherMiddle))
        #expect(QuickHash.compute(url: small)?.count == 16)
        #expect(QuickHash.compute(url: folder.url.appendingPathComponent("missing")) == nil)
    }

    @Test func exifDatesHonorOffsetsAndRejectGarbage() {
        let utc = TimeZone(identifier: "UTC") ?? .current
        let withOffset = MetadataExtractor.parseEXIFDate("2024:05:17 10:30:00", offset: "+02:00", defaultTimeZone: utc)
        #expect(withOffset == Date(timeIntervalSince1970: 1_715_934_600))
        let local = MetadataExtractor.parseEXIFDate("2024:05:17 10:30:00", offset: nil, defaultTimeZone: utc)
        #expect(local == Date(timeIntervalSince1970: 1_715_941_800))
        #expect(MetadataExtractor.parseEXIFDate("0000:00:00 00:00:00", offset: nil) == nil)
        #expect(MetadataExtractor.parseEXIFDate("garbage", offset: nil) == nil)
    }
}
