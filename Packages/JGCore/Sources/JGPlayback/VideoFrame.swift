import AVFoundation
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// The video frame on screen as a picture (D-80, W-75): decoded exactly at its time and at the video's own size
/// (no zoom, no overlay), saved as a PNG next to the video or handed to the pasteboard.
public enum VideoFrame {
    /// The frame at `seconds`. Matroska files are not supported (the system cannot read them).
    public static func image(of url: URL, at seconds: Double) async throws -> CGImage {
        guard !PlaybackController.isMatroska(url) else { throw SegmentExportError.unsupported }
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.appliesPreferredTrackTransform = true
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        return try await generator.image(at: CMTime(seconds: max(seconds, 0), preferredTimescale: 600)).image
    }

    /// "Clip 01-02.345.png", or "Clip 1-02-03.456.png" past an hour.
    public static func fileName(for video: URL, at seconds: Double) -> String {
        let millis = Int((max(seconds, 0) * 1000).rounded())
        let hours = millis / 3_600_000
        let minutes = millis / 60000 % 60
        let rest = String(format: "%02d.%03d", millis / 1000 % 60, millis % 1000)
        let stamp = hours > 0 ? String(format: "%d-%02d-", hours, minutes) + rest : String(format: "%02d-", minutes) + rest
        return video.deletingPathExtension().lastPathComponent + " " + stamp + ".png"
    }

    /// Writes `image` as a PNG next to `video`; never over a file ("… 2.png", "… 3.png", as Finder and the app's other
    /// exports name copies). Returns where it went.
    @discardableResult
    public static func save(_ image: CGImage, nextTo video: URL, at seconds: Double) throws -> URL {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
        let target = SegmentExporter.vacant(video.deletingLastPathComponent().appendingPathComponent(fileName(for: video, at: seconds)))
        try (data as Data).write(to: target, options: .withoutOverwriting)
        return target
    }
}
