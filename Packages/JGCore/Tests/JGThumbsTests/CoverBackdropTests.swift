import CoreGraphics
import Testing
@testable import JGThumbs

struct CoverBackdropTests {
    /// A 400 × 200 image: left half red, right half blue.
    func splitImage() throws -> CGImage {
        let context = try #require(CGContext(
            data: nil, width: 400, height: 200, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.setFillColor(red: 1, green: 0, blue: 0, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: 200, height: 200))
        context.setFillColor(red: 0, green: 0, blue: 1, alpha: 1)
        context.fill(CGRect(x: 200, y: 0, width: 200, height: 200))
        return try #require(context.makeImage())
    }

    @Test func backdropIsSmallOpaqueAndBlurred() async throws {
        let backdrop = try #require(await CoverBackdrop.render(splitImage()))
        #expect(max(backdrop.width, backdrop.height) == CoverBackdrop.side)
        #expect(backdrop.width == 2 * backdrop.height)
        let pixels = try rgba(backdrop)
        let middle = pixels[backdrop.height / 2 * backdrop.width + backdrop.width / 2]
        // The seam is mixed (blurred), the corners keep their color and stay opaque (no faded edges).
        #expect(middle.red > 40 && middle.blue > 40)
        #expect(pixels[0].alpha == 255 && pixels[0].red > 200)
    }

    struct Pixel {
        let red: UInt8
        let blue: UInt8
        let alpha: UInt8
    }

    private func rgba(_ image: CGImage) throws -> [Pixel] {
        var bytes = [UInt8](repeating: 0, count: image.width * image.height * 4)
        let context = try #require(CGContext(
            data: &bytes, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: image.width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return stride(from: 0, to: bytes.count, by: 4).map { Pixel(red: bytes[$0], blue: bytes[$0 + 2], alpha: bytes[$0 + 3]) }
    }
}
