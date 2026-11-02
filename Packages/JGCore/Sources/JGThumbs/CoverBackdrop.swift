import CoreGraphics
import CoreImage

/// The frosted backdrop behind an audio file (Settings → Appearance): its cover art shrunk to a few dozen pixels and
/// blurred once, so the view only stretches a tiny static image (no live blur filter while the song plays).
public enum CoverBackdrop {
    /// Longest side of the blurred image; stretched to the window it reads as heavy frosted glass.
    public static let side = 48
    /// Blur radius in pixels of the small image.
    static let radius = 4.0

    private static let context = CIContext(options: [.useSoftwareRenderer: false, .cacheIntermediates: false])

    /// A blurred, edge-to-edge copy of `cover`; nil if Core Image fails. Runs off the main thread.
    public static func render(_ cover: CGImage) async -> CGImage? {
        await Task.detached(priority: .utility) { make(cover) }.value
    }

    static func make(_ cover: CGImage) -> CGImage? {
        let input = CIImage(cgImage: cover)
        let scale = CGFloat(side) / max(input.extent.width, input.extent.height, 1)
        let small = input.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
        let extent = small.extent.integral
        // Clamping first keeps the edges from fading to transparent.
        let blurred = small.clampedToExtent().applyingGaussianBlur(sigma: radius).cropped(to: extent)
        return context.createCGImage(blurred, from: extent)
    }
}
