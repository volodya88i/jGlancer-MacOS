import Foundation
import ImageIO
import UniformTypeIdentifiers

/// Animated pictures (D-124): GIF and animated PNG, the formats ImageIO plays with `CGAnimateImageAtURLWithBlock`.
public enum AnimatedImage {
    /// Whether the file at `url` is a GIF or PNG with more than one frame. Reads the header only (no pixels); call it
    /// off the main thread.
    public static func isAnimated(at url: URL) -> Bool {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let type = CGImageSourceGetType(source).map({ $0 as String })
        else { return false }
        return [UTType.gif.identifier, UTType.png.identifier].contains(type) && CGImageSourceGetCount(source) > 1
    }
}
