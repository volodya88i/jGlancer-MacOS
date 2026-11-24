import AppKit
import JGDesign
import JGModel

/// Shapes and glyphs of grid tiles.
extension ThumbnailTileView {
    /// A small "+" centered on each corner of `square`.
    static func crosshairs(around square: CGRect) -> CGPath {
        let path = CGMutablePath()
        let half = JGMetrics.crosshairSize / 2
        for corner in [
            CGPoint(x: square.minX, y: square.minY), CGPoint(x: square.maxX, y: square.minY),
            CGPoint(x: square.minX, y: square.maxY), CGPoint(x: square.maxX, y: square.maxY),
        ] {
            path.move(to: CGPoint(x: corner.x - half, y: corner.y))
            path.addLine(to: CGPoint(x: corner.x + half, y: corner.y))
            path.move(to: CGPoint(x: corner.x, y: corner.y - half))
            path.addLine(to: CGPoint(x: corner.x, y: corner.y + half))
        }
        return path
    }

    static func aspectFit(_ size: CGSize, in rect: CGRect) -> CGRect {
        guard size.width > 0, size.height > 0 else { return rect }
        let scale = min(rect.width / size.width, rect.height / size.height)
        let fitted = CGSize(width: (size.width * scale).rounded(), height: (size.height * scale).rounded())
        return CGRect(x: rect.midX - fitted.width / 2, y: rect.midY - fitted.height / 2, width: fitted.width, height: fitted.height)
    }

    /// A tinted SF Symbol for tiles without a thumbnail, at the screen's scale (`SymbolRaster`).
    static func glyph(for kind: MediaKind, isCloudOnly: Bool = false, appearance: NSAppearance, scale: CGFloat) -> CGImage? {
        let name = switch kind {
        case _ where isCloudOnly: "icloud"
        case .photo: "photo"
        case .video: "film"
        case .audio: "waveform"
        }
        var color = NSColor.gray
        appearance.performAsCurrentDrawingAppearance {
            color = JGColor.textTertiary.nsColor.usingColorSpace(.sRGB) ?? .gray
        }
        return SymbolRaster.image(name, pointSize: JGMetrics.tileGlyphSize, weight: .light, color: color, scale: scale)
    }
}
