import CoreGraphics
import CoreMedia
import Foundation
import VideoToolbox

/// A still frame of a Matroska video (D-71): the first keyframe at or after min(1 s, 10 %) of the duration,
/// decoded with VideoToolbox and scaled down to `maxPixelSize`. Nil when the video cannot be decoded.
public enum MatroskaThumbnail {
    public static func image(at url: URL, maxPixelSize: Int) -> CGImage? {
        guard let file = try? MatroskaFile(url: url),
              let track = file.tracks.first(where: { $0.kind == .video && MatroskaCodecs.isSupported($0) }),
              let format = MatroskaCodecs.formatDescription(for: track)
        else { return nil }
        let target = min(1, (file.duration ?? 0) * 0.1)
        var reader = file.packets(from: file.clusterOffset(before: target))
        var frame: Data?
        var fallback: Data?
        while let packet = reader.next() {
            guard packet.track == track.number, packet.isKeyframe, let data = packet.frames.first else { continue }
            fallback = fallback ?? data
            if packet.time >= target - 0.001 {
                frame = data
                break
            }
        }
        guard let data = frame ?? fallback, let image = decode(data, format: format) else { return nil }
        return scaled(image, maxPixelSize: maxPixelSize)
    }

    private static func decode(_ data: Data, format: CMFormatDescription) -> CGImage? {
        var session: VTDecompressionSession?
        let attributes = [kCVPixelBufferPixelFormatTypeKey: kCVPixelFormatType_32BGRA] as CFDictionary
        guard VTDecompressionSessionCreate(
            allocator: nil, formatDescription: format, decoderSpecification: nil, imageBufferAttributes: attributes,
            outputCallback: nil, decompressionSessionOut: &session
        ) == noErr, let session else { return nil }
        defer { VTDecompressionSessionInvalidate(session) }
        var block: CMBlockBuffer?
        CMBlockBufferCreateWithMemoryBlock(
            allocator: nil, memoryBlock: nil, blockLength: data.count, blockAllocator: nil, customBlockSource: nil,
            offsetToData: 0, dataLength: data.count, flags: kCMBlockBufferAssureMemoryNowFlag, blockBufferOut: &block
        )
        guard let block else { return nil }
        let copied = data.withUnsafeBytes { bytes in
            bytes.baseAddress.map {
                CMBlockBufferReplaceDataBytes(with: $0, blockBuffer: block, offsetIntoDestination: 0, dataLength: data.count)
            }
        }
        guard copied == noErr else { return nil }
        var sample: CMSampleBuffer?
        var size = data.count
        CMSampleBufferCreateReady(
            allocator: nil, dataBuffer: block, formatDescription: format, sampleCount: 1, sampleTimingEntryCount: 0,
            sampleTimingArray: nil, sampleSizeEntryCount: 1, sampleSizeArray: &size, sampleBufferOut: &sample
        )
        guard let sample else { return nil }
        let result = DecodedFrame()
        VTDecompressionSessionDecodeFrame(session, sampleBuffer: sample, flags: [], infoFlagsOut: nil) { status, _, buffer, _, _ in
            guard status == noErr, let buffer else { return }
            var image: CGImage?
            VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &image)
            result.image = image
        }
        VTDecompressionSessionWaitForAsynchronousFrames(session)
        return result.image
    }

    private static func scaled(_ image: CGImage, maxPixelSize: Int) -> CGImage? {
        let scale = min(1, Double(maxPixelSize) / Double(max(image.width, image.height)))
        guard scale < 1 else { return image }
        let width = Int(Double(image.width) * scale)
        let height = Int(Double(image.height) * scale)
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()
    }
}

/// The decoded frame, set by VideoToolbox's callback and read after waiting for it.
private final class DecodedFrame: @unchecked Sendable {
    var image: CGImage?
}
