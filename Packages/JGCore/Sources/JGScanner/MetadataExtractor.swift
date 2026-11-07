import AVFoundation
import Foundation
import ImageIO
import JGMatroska
import JGModel
import JGStore

/// Stage 2: reads dimensions, orientation, duration, frame rate, codec and capture date without
/// decoding pixels, plus the quick hash (docs/ARCHITECTURE.md §5).
public struct MetadataExtractor: Sendable {
    public init() {}

    /// Extracts metadata for one pending asset. Never throws: failures become `.failed` updates.
    public func extract(_ item: PendingMetadataItem) async -> MetadataUpdate {
        // Gone to the cloud since it was listed: reading it would download it, so it waits (D-124).
        if CloudFile.isDataless(atPath: item.url.path) {
            return MetadataUpdate(id: item.id, modifiedAt: item.modifiedAt, state: .pending)
        }
        let hash = QuickHash.compute(url: item.url)
        switch item.kind {
        case .photo:
            return photo(item, hash: hash)
        case .video, .audio:
            return await audiovisual(item, hash: hash)
        }
    }

    private func photo(_ item: PendingMetadataItem, hash: Data?) -> MetadataUpdate {
        let options = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(item.url as CFURL, options),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, options) as? [CFString: Any],
              let pixelWidth = properties[kCGImagePropertyPixelWidth] as? Int,
              let pixelHeight = properties[kCGImagePropertyPixelHeight] as? Int
        else {
            return MetadataUpdate(id: item.id, modifiedAt: item.modifiedAt, state: .failed, quickHash: hash)
        }
        let orientation = properties[kCGImagePropertyOrientation] as? Int ?? 1
        let isRotated = (5 ... 8).contains(orientation)
        return MetadataUpdate(
            id: item.id, modifiedAt: item.modifiedAt, state: .extracted,
            width: isRotated ? pixelHeight : pixelWidth,
            height: isRotated ? pixelWidth : pixelHeight,
            orientation: orientation,
            capturedAt: Self.captureDate(properties),
            quickHash: hash
        )
    }

    /// Matroska: duration, picture size and frame rate from the file's header (D-71).
    private func matroska(_ item: PendingMetadataItem, hash: Data?) -> MetadataUpdate {
        guard let file = try? MatroskaFile(url: item.url) else {
            return MetadataUpdate(id: item.id, modifiedAt: item.modifiedAt, state: .failed, quickHash: hash)
        }
        let video = file.tracks.first { $0.kind == .video }
        let audio = file.tracks.first { $0.kind == .audio }
        return MetadataUpdate(
            id: item.id, modifiedAt: item.modifiedAt, state: .extracted,
            width: video.map { $0.displayWidth ?? $0.width }, height: video.map { $0.displayHeight ?? $0.height },
            duration: file.duration, frameRate: video?.defaultDuration.map { 1 / $0 },
            codec: (video ?? audio)?.codecID, quickHash: hash
        )
    }

    private func audiovisual(_ item: PendingMetadataItem, hash: Data?) async -> MetadataUpdate {
        if ["mkv", "mka", "webm", "mk3d"].contains(item.url.pathExtension.lowercased()) {
            return matroska(item, hash: hash)
        }
        let asset = AVURLAsset(url: item.url)
        do {
            let (playable, duration) = try await asset.load(.isPlayable, .duration)
            guard playable else {
                return MetadataUpdate(id: item.id, modifiedAt: item.modifiedAt, state: .failed, quickHash: hash)
            }
            var width: Int?
            var height: Int?
            var frameRate: Double?
            var codec: String?
            if let video = try await asset.loadTracks(withMediaType: .video).first {
                let (size, transform, rate, formats) = try await video.load(
                    .naturalSize, .preferredTransform, .nominalFrameRate, .formatDescriptions
                )
                let display = size.applying(transform)
                width = Int(abs(display.width).rounded())
                height = Int(abs(display.height).rounded())
                frameRate = rate > 0 ? Double(rate) : nil
                codec = formats.first.map(Self.fourCharacterCode)
            } else if let audio = try await asset.loadTracks(withMediaType: .audio).first {
                codec = try await audio.load(.formatDescriptions).first.map(Self.fourCharacterCode)
            }
            var captured: Date?
            if let creation = try await asset.load(.creationDate) {
                captured = try await creation.load(.dateValue)
            }
            return MetadataUpdate(
                id: item.id, modifiedAt: item.modifiedAt, state: .extracted, width: width, height: height,
                duration: duration.isNumeric ? duration.seconds : nil, frameRate: frameRate, codec: codec,
                capturedAt: captured, quickHash: hash
            )
        } catch {
            return MetadataUpdate(id: item.id, modifiedAt: item.modifiedAt, state: .failed, quickHash: hash)
        }
    }

    static func fourCharacterCode(_ format: CMFormatDescription) -> String {
        let code = CMFormatDescriptionGetMediaSubType(format)
        let bytes = [24, 16, 8, 0].map { UInt8((code >> $0) & 0xFF) }
        let text = String(bytes: bytes, encoding: .macOSRoman) ?? String(code)
        return text.trimmingCharacters(in: .whitespaces)
    }

    /// EXIF `DateTimeOriginal` (with `OffsetTimeOriginal` when present, else the current time zone),
    /// falling back to `DateTimeDigitized` and TIFF `DateTime`.
    static func captureDate(_ properties: [CFString: Any]) -> Date? {
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let text = exif[kCGImagePropertyExifDateTimeOriginal] as? String
            ?? exif[kCGImagePropertyExifDateTimeDigitized] as? String
            ?? tiff[kCGImagePropertyTIFFDateTime] as? String
        guard let text else { return nil }
        let offset = exif[kCGImagePropertyExifOffsetTimeOriginal] as? String
        return parseEXIFDate(text, offset: offset)
    }

    /// Parses `yyyy:MM:dd HH:mm:ss` with an optional `±HH:mm` offset.
    static func parseEXIFDate(_ text: String, offset: String?, defaultTimeZone: TimeZone = .current) -> Date? {
        let numbers = text.split(whereSeparator: { ": ".contains($0) }).compactMap { Int($0) }
        guard numbers.count >= 6, numbers[0] > 0 else { return nil }
        var timeZone = defaultTimeZone
        if let offset, offset.count >= 6, let sign = offset.first, "+-".contains(sign) {
            let parts = offset.dropFirst().split(separator: ":").compactMap { Int($0) }
            if parts.count == 2 {
                let seconds = (parts[0] * 3600 + parts[1] * 60) * (sign == "-" ? -1 : 1)
                timeZone = TimeZone(secondsFromGMT: seconds) ?? defaultTimeZone
            }
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar.date(from: DateComponents(
            year: numbers[0], month: numbers[1], day: numbers[2],
            hour: numbers[3], minute: numbers[4], second: numbers[5]
        ))
    }
}
