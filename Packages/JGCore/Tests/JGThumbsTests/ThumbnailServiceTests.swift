import CoreGraphics
import Foundation
import JGModel
import JGTestSupport
import Testing
@testable import JGThumbs

/// Counts generations; optionally slow, to observe merging and cancellation.
final class CountingGenerator: ThumbnailGenerating, @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0
    private var cancellations = 0
    let delay: Duration
    let produces: Bool

    init(delay: Duration = .zero, produces: Bool = true) {
        self.delay = delay
        self.produces = produces
    }

    var callCount: Int {
        lock.withLock { calls }
    }

    var cancellationCount: Int {
        lock.withLock { cancellations }
    }

    func generate(_: ThumbnailRequest, maxPixelSize: Int) async -> CGImage? {
        lock.withLock { calls += 1 }
        do {
            try await Task.sleep(for: delay)
        } catch {
            lock.withLock { cancellations += 1 }
            return nil
        }
        return produces ? Self.image(side: maxPixelSize / 2) : nil
    }

    static func image(side: Int) -> CGImage? {
        CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        )?.makeImage()
    }
}

func request(
    _ id: Int64,
    bucket: ThumbnailBucket = .medium,
    modified: TimeInterval = 0,
    url: URL? = nil,
    kind: MediaKind = .photo
) -> ThumbnailRequest {
    ThumbnailRequest(
        assetID: id, url: url ?? URL(fileURLWithPath: "/nonexistent/\(id).jpg"), kind: kind, typeIdentifier: nil,
        modifiedAt: Date(timeIntervalSince1970: modified), duration: nil, bucket: bucket
    )
}

struct ThumbnailServiceTests {
    @Test func concurrentRequestsShareOneGeneration() async throws {
        let generator = CountingGenerator(delay: .milliseconds(100))
        let service = try ThumbnailService(disk: ThumbnailDiskCache.inMemory(), generator: generator)
        async let first = service.thumbnail(for: request(1), priority: .visible)
        async let second = service.thumbnail(for: request(1), priority: .nearby)
        let images = await [first, second]
        #expect(images.allSatisfy { $0?.width == 160 })
        #expect(generator.callCount == 1)
    }

    @Test func memoryThenDiskServeRepeats() async throws {
        let disk = try ThumbnailDiskCache.inMemory()
        let generator = CountingGenerator()
        let service = ThumbnailService(disk: disk, generator: generator)
        _ = await service.thumbnail(for: request(1), priority: .visible)
        #expect(service.cachedThumbnail(for: request(1))??.width == 160)
        let fresh = ThumbnailService(disk: disk, generator: generator)
        #expect(fresh.cachedThumbnail(for: request(1)) == nil)
        #expect(await fresh.thumbnail(for: request(1), priority: .visible)?.width == 160)
        #expect(generator.callCount == 1)
    }

    @Test func missingThumbnailsAreRememberedAsNone() async throws {
        let generator = CountingGenerator(produces: false)
        let disk = try ThumbnailDiskCache.inMemory()
        let service = ThumbnailService(disk: disk, generator: generator)
        #expect(await service.thumbnail(for: request(1), priority: .visible) == nil)
        let cached = service.cachedThumbnail(for: request(1))
        // Known to have no thumbnail: an entry whose image is nil.
        #expect(cached.map { $0 == nil } == true)
        #expect(try await disk.data(for: request(1).key) == Data())
        _ = await ThumbnailService(disk: disk, generator: generator).thumbnail(for: request(1), priority: .visible)
        #expect(generator.callCount == 1)
    }

    @Test func smallRequestsReuseMediumAndModifiedFilesRegenerate() async throws {
        let generator = CountingGenerator()
        let service = try ThumbnailService(disk: ThumbnailDiskCache.inMemory(), generator: generator)
        _ = await service.thumbnail(for: request(1, bucket: .medium), priority: .visible)
        _ = await service.thumbnail(for: request(1, bucket: .small), priority: .visible)
        #expect(generator.callCount == 1)
        _ = await service.thumbnail(for: request(1, bucket: .large), priority: .visible)
        _ = await service.thumbnail(for: request(1, bucket: .medium, modified: 60), priority: .visible)
        #expect(generator.callCount == 3)
    }

    @Test func cancellingTheOnlyWaiterCancelsTheGeneration() async throws {
        let generator = CountingGenerator(delay: .seconds(5))
        let service = try ThumbnailService(disk: ThumbnailDiskCache.inMemory(), generator: generator)
        let waiting = Task { await service.thumbnail(for: request(1), priority: .visible) }
        try await Task.sleep(for: .milliseconds(100))
        waiting.cancel()
        #expect(await waiting.value == nil)
        #expect(try await eventually(timeout: .seconds(2)) { generator.cancellationCount == 1 })
        #expect(service.cachedThumbnail(for: request(1)) == nil)
    }
}

/// The real generators on generated media.
struct ThumbnailGeneratorTests {
    private func generate(_ url: URL, kind: MediaKind, maxPixelSize: Int = 320) async -> CGImage? {
        await ThumbnailGenerator().generate(request(1, url: url, kind: kind), maxPixelSize: maxPixelSize)
    }

    @Test func photosAreDownsampledWithOrientationAndNeverUpscaled() async throws {
        let folder = try TemporaryDirectory()
        let large = folder.url.appendingPathComponent("large.jpg")
        try MediaFactory.jpeg(at: large, width: 1000, height: 500)
        let image = try #require(await generate(large, kind: .photo))
        #expect(image.width == 320 && image.height == 160)
        let rotated = folder.url.appendingPathComponent("rotated.jpg")
        try MediaFactory.jpeg(at: rotated, width: 64, height: 48, orientation: 6)
        let small = try #require(await generate(rotated, kind: .photo))
        #expect(small.width == 48 && small.height == 64)
        let broken = try folder.write("broken.jpg", "not an image")
        #expect(await generate(broken, kind: .photo) == nil)
    }

    @Test func embeddedPreviewsAreUsedOnlyWhenBigEnoughAndSameShape() throws {
        let landscape = try #require(CountingGenerator.image(side: 320))
        #expect(PhotoDecoder.isUsable(landscape, fullWidth: 4000, fullHeight: 4000, maxPixelSize: 320))
        #expect(!PhotoDecoder.isUsable(landscape, fullWidth: 4000, fullHeight: 4000, maxPixelSize: 640))
        #expect(PhotoDecoder.isUsable(landscape, fullWidth: 300, fullHeight: 300, maxPixelSize: 640))
        // A square preview of a 4:3 photo is padded (black bars): rejected.
        #expect(!PhotoDecoder.isUsable(landscape, fullWidth: 4000, fullHeight: 3000, maxPixelSize: 320))
        #expect(PhotoDecoder.displaySize(width: 4000, height: 3000, orientation: 6) == (3000, 4000))
    }

    @Test func heicWithEmbeddedPreviewUsesIt() throws {
        let folder = try TemporaryDirectory()
        let url = folder.url.appendingPathComponent("photo.heic")
        try MediaFactory.heic(at: url, width: 2000, height: 1500, embedPreview: true)
        let image = try #require(PhotoDecoder.image(at: url, maxPixelSize: 320))
        #expect(image.width == 320 && image.height == 240)
    }

    @Test func fullResolutionAppliesOrientationAndHeaderSizeIsCheap() throws {
        let folder = try TemporaryDirectory()
        let url = folder.url.appendingPathComponent("portrait.jpg")
        try MediaFactory.jpeg(at: url, width: 1200, height: 800, orientation: 6)
        #expect(PhotoDecoder.displaySize(of: url) == CGSize(width: 800, height: 1200))
        let full = try #require(PhotoDecoder.fullResolution(at: url))
        #expect(full.width == 800 && full.height == 1200)
        let screen = try #require(PhotoDecoder.image(at: url, maxPixelSize: 600))
        #expect(screen.width == 400 && screen.height == 600)
        #expect(PhotoDecoder.displaySize(of: folder.url.appendingPathComponent("missing.jpg")) == nil)
    }

    @Test func videoPosterRespectsTheSizeLimit() async throws {
        let folder = try TemporaryDirectory()
        let url = folder.url.appendingPathComponent("clip.mov")
        try await MediaFactory.mov(at: url, width: 640, height: 320, frames: 30, fps: 30)
        let image = try #require(await generate(url, kind: .video, maxPixelSize: 160))
        #expect(image.width == 160 && image.height == 80)
    }

    @Test func audioArtworkOrNothing() async throws {
        let folder = try TemporaryDirectory()
        let plain = folder.url.appendingPathComponent("tone.wav")
        try MediaFactory.wav(at: plain, seconds: 0.5)
        #expect(await generate(plain, kind: .audio) == nil)
        if #available(macOS 15, *) {
            let tagged = folder.url.appendingPathComponent("song.m4a")
            try await MediaFactory.m4aWithArtwork(at: tagged, coverSide: 600)
            let cover = try #require(await generate(tagged, kind: .audio))
            #expect(cover.width == 320 && cover.height == 320)
        }
    }

    @Test func codecRoundTripsOpaqueAndAlphaImages() throws {
        let opaque = try #require(CountingGenerator.image(side: 32))
        let data = try #require(ThumbnailCodec.encode(opaque))
        #expect(data.starts(with: [0xFF, 0xD8]))
        #expect(ThumbnailCodec.decode(data)?.width == 32)
        let alpha = try #require(CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )?.makeImage())
        let png = try #require(ThumbnailCodec.encode(alpha, preserveAlpha: true))
        #expect(png.starts(with: [0x89, 0x50, 0x4E, 0x47]))
        #expect(try #require(ThumbnailCodec.encode(alpha)).starts(with: [0xFF, 0xD8]))
        #expect(ThumbnailCodec.preservesAlpha(typeIdentifier: "public.png"))
        #expect(!ThumbnailCodec.preservesAlpha(typeIdentifier: "public.heic"))
        #expect(!ThumbnailCodec.preservesAlpha(typeIdentifier: nil))
    }

    @Test func thumbnailsKeepWideGamutColors() throws {
        let wideGamut = try #require(CGColorSpace(name: CGColorSpace.displayP3))
        let context = try #require(CGContext(
            data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0, space: wideGamut,
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ))
        context.setFillColor(CGColor(colorSpace: wideGamut, components: [1, 0, 0, 1]) ?? .black)
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let red = try #require(context.makeImage())
        let shown = try #require(ThumbnailCodec.displayReady(red))
        #expect(shown.colorSpace?.name == CGColorSpace.displayP3)
        // Stored and read back from cache.sqlite, still Display P3 (sRGB would clip the red).
        let stored = try #require(ThumbnailCodec.encode(shown))
        #expect(ThumbnailCodec.decode(stored)?.colorSpace?.name == CGColorSpace.displayP3)
    }
}
