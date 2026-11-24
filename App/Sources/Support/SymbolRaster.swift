import AppKit

/// SF Symbols drawn into bitmaps for layers, at the screen's own scale. `NSImage.cgImage(forProposedRect:…)` picks a
/// scale of its own (the main screen's), so on a 1× monitor a layer showed the glyph twice as big and blurred.
@MainActor
enum SymbolRaster {
    private static var cache: [String: CGImage] = [:]

    /// `name` at `pointSize` in `color`, `scale` pixels per point; show it with `contentsScale = scale`.
    static func image(_ name: String, pointSize: CGFloat, weight: NSFont.Weight, color: NSColor, scale: CGFloat) -> CGImage? {
        let srgb = color.usingColorSpace(.sRGB) ?? color
        let key = "\(name)|\(pointSize)|\(weight.rawValue)|\(scale)|\(srgb.redComponent)|\(srgb.greenComponent)|\(srgb.blueComponent)"
        if let cached = cache[key] {
            return cached
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: weight)
            .applying(NSImage.SymbolConfiguration(paletteColors: [srgb]))
        guard let symbol = NSImage(systemSymbolName: name, accessibilityDescription: nil)?.withSymbolConfiguration(configuration),
              symbol.size.width > 0, symbol.size.height > 0,
              let context = CGContext(
                  data: nil, width: Int((symbol.size.width * scale).rounded(.up)), height: Int((symbol.size.height * scale).rounded(.up)),
                  bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
                  bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
              )
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        symbol.draw(in: CGRect(origin: .zero, size: symbol.size))
        NSGraphicsContext.restoreGraphicsState()
        let image = context.makeImage()
        cache[key] = image
        return image
    }
}
