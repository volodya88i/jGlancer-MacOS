import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import JGMatroska
import QuickLookThumbnailing
import UniformTypeIdentifiers

/// Produces a thumbnail from the original file. Injected into `ThumbnailService` (fakes in tests).
public protocol ThumbnailGenerating: Sendable {
    /// A decoded image whose longest side is at most `maxPixelSize`, or nil if the file has none.
    func generate(_ request: ThumbnailRequest, maxPixelSize: Int) async -> CGImage?
}

/// The real generators: ImageIO for photos (QuickLook as fallback), a poster frame for video,
/// embedded artwork for audio (docs/ARCHITECTURE.md §6). Never upscales.
public struct ThumbnailGenerator: ThumbnailGenerating {
    public init() {}

    public func generate(_ request: ThumbnailRequest, maxPixelSize: Int) async -> CGImage? {
        switch request.kind {
        case .photo:
            if let image = PhotoDecoder.image(at: request.url, maxPixelSize: maxPixelSize) {
                return image
            }
            return await Self.quickLook(request.url, maxPixelSize: maxPixelSize)
        case .video where ["mkv", "webm", "mk3d"].contains(request.url.pathExtension.lowercased()):
            let url = request.url
            return await Task.detached(priority: .utility) { MatroskaThumbnail.image(at: url, maxPixelSize: maxPixelSize) }.value
        case .video:
            return await Self.poster(request, maxPixelSize: maxPixelSize)
        case .audio:
            return await Self.artwork(request.url, maxPixelSize: maxPixelSize)
        }
    }

    static func quickLook(_ url: URL, maxPixelSize: Int) async -> CGImage? {
        let size = CGSize(width: maxPixelSize, height: maxPixelSize)
        let request = QLThumbnailGenerator.Request(fileAt: url, size: size, scale: 1, representationTypes: .thumbnail)
        return try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request).cgImage
    }

    /// A frame at min(1 s, 10 % of the duration), nearest keyframe for speed.
    static func poster(_ request: ThumbnailRequest, maxPixelSize: Int) async -> CGImage? {
        let asset = AVURLAsset(url: request.url)
        var duration = request.duration
        if duration == nil {
            duration = try? await asset.load(.duration).seconds
        }
        let seconds = min(1, max(0, (duration ?? 0) * 0.1))
        let generator = AVAssetImageGenerator(asset: asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = CGSize(width: maxPixelSize, height: maxPixelSize)
        generator.requestedTimeToleranceBefore = CMTime(seconds: 1, preferredTimescale: 600)
        generator.requestedTimeToleranceAfter = CMTime(seconds: 1, preferredTimescale: 600)
        return try? await generator.image(at: CMTime(seconds: seconds, preferredTimescale: 600)).image
    }

    /// Embedded cover art, downsampled; nil when the file has none (the UI draws a generated tile).
    static func artwork(_ url: URL, maxPixelSize: Int) async -> CGImage? {
        let asset = AVURLAsset(url: url)
        guard let metadata = try? await asset.load(.commonMetadata),
              let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: .commonIdentifierArtwork).first,
              let data = try? await item.load(.dataValue),
              let source = CGImageSourceCreateWithData(data as CFData, nil)
        else { return nil }
        return PhotoDecoder.thumbnail(from: source, maxPixelSize: maxPixelSize, preferEmbedded: false)
    }
}

/// Encoding of thumbnails for the disk cache: JPEG, or PNG when transparency must survive.
enum ThumbnailCodec {
    static let jpegQuality = 0.8

    /// Source types whose transparency is kept (screenshots, graphics, icons). Photos, video frames
    /// and HEIC previews are opaque even when ImageIO reports an alpha channel.
    static let transparentTypes: [UTType] = [.png, .gif, .webP, .tiff, .ico, .icns]

    static func preservesAlpha(typeIdentifier: String?) -> Bool {
        guard let type = typeIdentifier.flatMap(UTType.init) else { return false }
        return transparentTypes.contains { type.conforms(to: $0) }
    }

    static func encode(_ image: CGImage, preserveAlpha: Bool = false) -> Data? {
        let alpha = image.alphaInfo
        let hasAlpha = !(alpha == .none || alpha == .noneSkipFirst || alpha == .noneSkipLast)
        let type = hasAlpha && preserveAlpha ? UTType.png : UTType.jpeg
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data as CFMutableData, type.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: jpegQuality] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? data as Data : nil
    }

    /// Decodes immediately so the main thread never decodes when the image is shown.
    static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, [kCGImageSourceShouldCacheImmediately: true] as CFDictionary)
            .flatMap(displayReady)
    }

    /// Redraws `image` into a plain 32-bit BGRA bitmap (premultiplied, sRGB), the format Core Animation
    /// uploads without converting. Video frames (IOSurface-backed YUV) and odd ImageIO formats would
    /// otherwise be converted on the main thread when the tile is committed (dropped frames).
    static func displayReady(_ image: CGImage) -> CGImage? {
        let width = image.width
        let height = image.height
        guard width > 0, height > 0, let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return image }
        context.interpolationQuality = .none
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage() ?? image
    }
}
