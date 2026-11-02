import AVFoundation
import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

/// A unique temporary directory (canonical path, as FSEvents reports it), deleted afterwards.
public final class TemporaryDirectory {
    public let url: URL

    public init() throws {
        let created = FileManager.default.temporaryDirectory
            .appendingPathComponent("JGScannerTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: created, withIntermediateDirectories: true)
        guard let resolved = realpath(created.path, nil) else { throw CocoaError(.fileNoSuchFile) }
        defer { free(resolved) }
        url = URL(fileURLWithPath: String(cString: resolved), isDirectory: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    /// Writes `contents` at `relativePath`, creating folders.
    @discardableResult
    public func write(_ relativePath: String, _ contents: String = "x") throws -> URL {
        let target = url.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(contents.utf8).write(to: target)
        return target
    }

    public func move(_ source: String, to destination: String) throws {
        let target = url.appendingPathComponent(destination)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.moveItem(at: url.appendingPathComponent(source), to: target)
    }

    public func remove(_ relativePath: String) throws {
        try FileManager.default.removeItem(at: url.appendingPathComponent(relativePath))
    }
}

/// Generates small real media files for metadata tests.
public enum MediaFactory {
    public static func jpeg(
        at url: URL, width: Int, height: Int, orientation: Int = 1, captured: String? = nil, extra: [CFString: Any] = [:]
    ) throws {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw CocoaError(.fileWriteUnknown) }
        context.setFillColor(CGColor(red: 0.3, green: 0.5, blue: 0.7, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage(),
              let target = CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        var properties: [CFString: Any] = [kCGImagePropertyOrientation: orientation]
        properties.merge(extra) { _, new in new }
        if let captured {
            properties[kCGImagePropertyExifDictionary] = [
                kCGImagePropertyExifDateTimeOriginal: captured, kCGImagePropertyExifOffsetTimeOriginal: "+02:00",
            ]
        }
        CGImageDestinationAddImage(target, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(target) else { throw CocoaError(.fileWriteUnknown) }
    }

    /// A HEIC photo, optionally with an embedded preview as iPhones write them.
    public static func heic(at url: URL, width: Int, height: Int, embedPreview: Bool) throws {
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw CocoaError(.fileWriteUnknown) }
        context.setFillColor(CGColor(red: 0.6, green: 0.4, blue: 0.2, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        guard let image = context.makeImage(),
              let target = CGImageDestinationCreateWithURL(url as CFURL, UTType.heic.identifier as CFString, 1, nil)
        else { throw CocoaError(.fileWriteUnknown) }
        CGImageDestinationAddImage(target, image, [kCGImageDestinationEmbedThumbnail: embedPreview] as CFDictionary)
        guard CGImageDestinationFinalize(target) else { throw CocoaError(.fileWriteUnknown) }
    }

    /// A mono 8 kHz WAV: silence, or a 440 Hz tone of `amplitude` during the first `loudSeconds` (all by default).
    public static func wav(at url: URL, seconds: Double, amplitude: Float = 0, loudSeconds: Double? = nil) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 8000, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        let frames = AVAudioFrameCount(8000 * seconds)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else {
            throw CocoaError(.fileWriteUnknown)
        }
        buffer.frameLength = frames
        if amplitude != 0, let channel = buffer.floatChannelData?[0] {
            let loudFrames = min(Int(8000 * (loudSeconds ?? seconds)), Int(frames))
            for frame in 0 ..< loudFrames {
                channel[frame] = amplitude * sinf(Float(frame) * 2 * .pi * 440 / 8000)
            }
        }
        try file.write(from: buffer)
        if #available(macOS 15, *) {
            file.close()
        }
    }

    /// A short AAC file with an embedded JPEG cover (needs macOS 15 for the async export API).
    @available(macOS 15, *)
    public static func m4aWithArtwork(at url: URL, coverSide: Int) async throws {
        let raw = url.deletingLastPathComponent().appendingPathComponent("raw-\(UUID().uuidString).m4a")
        defer { try? FileManager.default.removeItem(at: raw) }
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1]
        do {
            let file = try AVAudioFile(forWriting: raw, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 44100) else {
                throw CocoaError(.fileWriteUnknown)
            }
            buffer.frameLength = 44100
            try file.write(from: buffer)
            file.close()
        }
        let cover = url.deletingLastPathComponent().appendingPathComponent("cover-\(UUID().uuidString).jpg")
        defer { try? FileManager.default.removeItem(at: cover) }
        try jpeg(at: cover, width: coverSide, height: coverSide)
        let artwork = AVMutableMetadataItem()
        artwork.identifier = .iTunesMetadataCoverArt
        artwork.value = try Data(contentsOf: cover) as NSData
        artwork.dataType = kCMMetadataBaseDataType_JPEG as String
        guard let session = AVAssetExportSession(asset: AVURLAsset(url: raw), presetName: AVAssetExportPresetPassthrough) else {
            throw CocoaError(.fileWriteUnknown)
        }
        session.metadata = [artwork]
        try await session.export(to: url, as: .m4a)
    }

    public static func mov(at url: URL, width: Int, height: Int, frames: Int, fps: Int32) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
        ])
        input.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input, sourcePixelBufferAttributes: [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
            kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
        ])
        writer.add(input)
        writer.startWriting()
        writer.startSession(atSourceTime: .zero)
        for frame in 0 ..< frames {
            while !input.isReadyForMoreMediaData {
                try await Task.sleep(for: .milliseconds(2))
            }
            var buffer: CVPixelBuffer?
            if let pool = adaptor.pixelBufferPool {
                CVPixelBufferPoolCreatePixelBuffer(nil, pool, &buffer)
            }
            guard let buffer else { throw CocoaError(.fileWriteUnknown) }
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else { throw writer.error ?? CocoaError(.fileWriteUnknown) }
    }
}

/// Polls `condition` until it holds or `timeout` passes (for file-system events, which arrive asynchronously).
public func eventually(timeout: Duration = .seconds(10), _ condition: () async throws -> Bool) async throws -> Bool {
    let clock = ContinuousClock()
    let deadline = clock.now + timeout
    while clock.now < deadline {
        if try await condition() {
            return true
        }
        try await Task.sleep(for: .milliseconds(100))
    }
    return try await condition()
}
