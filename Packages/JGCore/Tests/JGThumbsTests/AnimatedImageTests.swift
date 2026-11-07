import CoreGraphics
import Foundation
import ImageIO
import JGTestSupport
import Testing
import UniformTypeIdentifiers
@testable import JGThumbs

struct AnimatedImageTests {
    /// A `frames`-frame image of `type` (GIF or PNG; more than one PNG frame makes an APNG) at `url`.
    private func write(_ url: URL, type: UTType, frames: Int) throws {
        let destination = try #require(CGImageDestinationCreateWithURL(url as CFURL, type.identifier as CFString, frames, nil))
        for index in 0 ..< frames {
            let context = try #require(CGContext(
                data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ))
            context.setFillColor(gray: CGFloat(index) / CGFloat(max(frames, 1)), alpha: 1)
            context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
            let delay: [CFString: Any] = type == .gif
                ? [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: 0.1]]
                : [kCGImagePropertyPNGDictionary: [kCGImagePropertyAPNGDelayTime: 0.1]]
            try CGImageDestinationAddImage(destination, #require(context.makeImage()), delay as CFDictionary)
        }
        #expect(CGImageDestinationFinalize(destination))
    }

    @Test func gifsAndPNGsWithSeveralFramesAreAnimated() throws {
        let folder = try TemporaryDirectory()
        struct Case {
            let name: String
            let type: UTType
            let frames: Int
            let isAnimated: Bool
        }
        let cases = [
            Case(name: "loop.gif", type: .gif, frames: 3, isAnimated: true),
            Case(name: "still.gif", type: .gif, frames: 1, isAnimated: false),
            Case(name: "loop.png", type: .png, frames: 2, isAnimated: true),
            Case(name: "still.png", type: .png, frames: 1, isAnimated: false),
            Case(name: "pages.tiff", type: .tiff, frames: 2, isAnimated: false),
        ]
        for item in cases {
            let url = folder.url.appendingPathComponent(item.name)
            try write(url, type: item.type, frames: item.frames)
            #expect(AnimatedImage.isAnimated(at: url) == item.isAnimated, "\(item.name)")
        }
        #expect(!AnimatedImage.isAnimated(at: folder.url.appendingPathComponent("missing.gif")))
    }
}
