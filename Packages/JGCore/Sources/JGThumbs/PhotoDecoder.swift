import CoreGraphics
import Foundation
import ImageIO

/// Decodes photos for display: downsampled at decode time with EXIF orientation applied, decoded immediately
/// (never on the main thread), color space preserved (docs/ARCHITECTURE.md §6, §8).
public enum PhotoDecoder {
    /// Pixel size after orientation, read from the header without decoding; nil if unreadable.
    public static func displaySize(of url: URL) -> CGSize? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let size = headerSize(source)
        return size.width > 0 ? CGSize(width: size.width, height: size.height) : nil
    }

    /// An image whose longest side is at most `maxPixelSize` (never upscaled). The embedded preview (iPhone HEIC,
    /// RAW, many JPEGs) is used when it is big enough and has the image's proportions: about 7× faster than
    /// decoding a 12-MP HEIC (DECISIONS D-36); RAW files thus show their embedded preview.
    public static func image(at url: URL, maxPixelSize: Int) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let full = headerSize(source)
        // Without an embedded preview, "if absent" decodes the full image: one pass either way.
        if let embedded = thumbnail(from: source, maxPixelSize: maxPixelSize, preferEmbedded: true),
           isUsable(embedded, fullWidth: full.width, fullHeight: full.height, maxPixelSize: maxPixelSize)
        {
            return embedded
        }
        return thumbnail(from: source, maxPixelSize: maxPixelSize, preferEmbedded: false)
    }

    /// The full-resolution image with orientation applied (for zoom beyond fit).
    public static func fullResolution(at url: URL) -> CGImage? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary)
        else { return nil }
        let full = headerSize(source)
        guard full.width > 0 else { return nil }
        return thumbnail(from: source, maxPixelSize: max(full.width, full.height), preferEmbedded: false)
    }

    /// Whether a preview is large enough (never asking for more than the original has) and has the same
    /// proportions (some cameras pad previews with black bars).
    static func isUsable(_ image: CGImage, fullWidth: Int, fullHeight: Int, maxPixelSize: Int) -> Bool {
        guard fullWidth > 0, fullHeight > 0 else { return max(image.width, image.height) >= maxPixelSize }
        let needed = min(maxPixelSize, max(fullWidth, fullHeight))
        guard max(image.width, image.height) >= needed, image.height > 0 else { return false }
        let fullRatio = Double(fullWidth) / Double(fullHeight)
        let ratio = Double(image.width) / Double(image.height)
        return abs(ratio - fullRatio) / fullRatio < 0.02
    }

    /// Pixel size after EXIF orientation (5–8 swap width and height).
    static func displaySize(width: Int, height: Int, orientation: Int) -> (width: Int, height: Int) {
        (5 ... 8).contains(orientation) ? (height, width) : (width, height)
    }

    static func thumbnail(from source: CGImageSource, maxPixelSize: Int, preferEmbedded: Bool) -> CGImage? {
        let options: [CFString: Any] = [
            preferEmbedded ? kCGImageSourceCreateThumbnailFromImageIfAbsent : kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixelSize,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }

    private static func headerSize(_ source: CGImageSource) -> (width: Int, height: Int) {
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] ?? [:]
        return displaySize(
            width: properties[kCGImagePropertyPixelWidth] as? Int ?? 0,
            height: properties[kCGImagePropertyPixelHeight] as? Int ?? 0,
            orientation: properties[kCGImagePropertyOrientation] as? Int ?? 1
        )
    }
}
