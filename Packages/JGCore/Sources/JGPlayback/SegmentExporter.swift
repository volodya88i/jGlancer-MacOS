import AVFoundation
import Foundation
import JGModel

/// A part of a video or audio file to save as a new file (docs/DECISIONS.md D-73). Audio also takes the speed,
/// Keep Pitch and short fades it plays with; video is cut as it is.
public struct SegmentExportRequest: Equatable, Sendable {
    public let source: URL
    public let kind: MediaKind
    /// Seconds of the source.
    public let range: ClosedRange<Double>
    public var rate: Float = PlaybackSpeed.normal
    public var preservesPitch = true
    /// Fades of `SegmentExporter.fadeSeconds` at both ends (no clicks where the cut falls mid-wave).
    public var fades = false
    /// WAV, AIFF and FLAC stay in their format; off (or any other source): M4A (D-74).
    public var keepsAudioFormat = true
    /// The whole file, not a segment (D-107): audio with the speed and Keep Pitch but no fades, video copied unchanged.
    public var isWhole = false
    /// A video segment cut exactly at its bounds, encoded again as H.264 / AAC MP4 (D-108); off: the source's own
    /// samples from the keyframe before the start.
    public var isExact = false

    public init(source: URL, kind: MediaKind, range: ClosedRange<Double>) {
        self.source = source
        self.kind = kind
        self.range = range
    }

    /// The whole file of `duration` seconds (D-107).
    public static func whole(_ source: URL, kind: MediaKind, duration: Double) -> SegmentExportRequest {
        var request = SegmentExportRequest(source: source, kind: kind, range: 0 ... max(duration, 0))
        request.isWhole = true
        return request
    }
}

public enum SegmentExportError: Error, Sendable {
    /// Matroska, or a file without the needed track.
    case unsupported
    case failed
}

/// Saves segments (D-73, D-74). Video: the source's own samples (no re-encoding), cut from the keyframe before the
/// start with an edit list so players start exactly at it; the container stays (MOV, MP4, M4V; others become MOV).
/// Audio: decoded with the speed, pitch and fades applied, then encoded: WAV, AIFF and FLAC keep their format
/// (`keepsAudioFormat`), everything else becomes M4A — ALAC for lossless sources, AAC 256 kbit/s otherwise; up to
/// two channels.
public enum SegmentExporter {
    public static let fadeSeconds = 0.03
    static let aacBitRate = 256_000

    /// Whether a file of `kind` at `url` can be cut (not Matroska, which the system cannot write from).
    public static func canExport(_ url: URL, kind: MediaKind) -> Bool {
        kind != .photo && !PlaybackController.isMatroska(url)
    }

    /// Whether the whole file can be saved (D-107): audio that can be cut; video only as MP4, MOV or M4V, copied as it is.
    public static func canExportWhole(_ url: URL, kind: MediaKind) -> Bool {
        kind == .audio ? canExport(url, kind: kind) : kind == .video && copiedVideoExtensions.contains(url.pathExtension.lowercased())
    }

    static let copiedVideoExtensions: Set = ["mov", "mp4", "m4v"]

    /// The extension of the saved file.
    public static func fileExtension(for request: SegmentExportRequest) -> String {
        let source = request.source.pathExtension.lowercased()
        guard request.kind == .video else {
            let kept = ["wav": "wav", "wave": "wav", "aif": "aif", "aiff": "aiff", "aifc": "aiff", "flac": "flac"][source]
            return request.keepsAudioFormat ? kept ?? "m4a" : "m4a"
        }
        if request.isExact, !request.isWhole {
            return "mp4"
        }
        return copiedVideoExtensions.contains(source) ? source : "mov"
    }

    /// "Name (1m02.0s–1m15.4s).m4a", with the speed when it is not 1×.
    /// The whole file: "Name 1.25x.flac".
    public static func suggestedName(for request: SegmentExportRequest) -> String {
        let base = request.source.deletingPathExtension().lastPathComponent
        var name = request.isWhole ? base : "\(base) (\(stamp(request.range.lowerBound))–\(stamp(request.range.upperBound)))"
        if request.kind == .audio, request.rate != PlaybackSpeed.normal {
            name += " " + String(format: "%gx", Double(request.rate))
        }
        return name + "." + fileExtension(for: request)
    }

    static func stamp(_ seconds: Double) -> String {
        let tenths = Int((max(seconds, 0) * 10).rounded())
        return String(format: "%dm%02d.%ds", tenths / 600, tenths / 10 % 60, tenths % 10)
    }

    /// Writes the segment to `url` (which must not exist yet).
    public static func export(_ request: SegmentExportRequest, to url: URL) async throws {
        guard canExport(request.source, kind: request.kind), request.range.upperBound > request.range.lowerBound else {
            throw SegmentExportError.unsupported
        }
        if request.isWhole, request.kind == .video {
            guard canExportWhole(request.source, kind: .video) else { throw SegmentExportError.unsupported }
            try FileManager.default.copyItem(at: request.source, to: url)
        } else if request.kind == .video, request.isExact {
            try await exportExactVideo(request, to: url)
        } else if request.kind == .video {
            try await exportVideo(request, to: url)
        } else {
            try await AudioSegmentWriter(request: request, url: url).write()
        }
    }

    /// Exports to `url`, or to "Name 2.ext", "Name 3.ext"… when a file is already there (nothing is replaced),
    /// through a temporary file so the destination never shows a partial one. Returns where the file went.
    @discardableResult
    public static func save(_ request: SegmentExportRequest, to url: URL) async throws -> URL {
        let files = FileManager.default
        let folder = files.temporaryDirectory.appendingPathComponent("jGlancer-export-\(UUID().uuidString)")
        try files.createDirectory(at: folder, withIntermediateDirectories: true)
        // Only the temporary folder this call made is removed.
        defer { try? files.removeItem(at: folder) }
        let temporary = folder.appendingPathComponent(url.lastPathComponent)
        try await export(request, to: temporary)
        let target = vacant(url)
        try files.moveItem(at: temporary, to: target)
        return target
    }

    /// `url`, or the first "Name N.ext" next to it that does not exist.
    public static func vacant(_ url: URL) -> URL {
        let files = FileManager.default
        guard files.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent
        let folder = url.deletingLastPathComponent()
        var number = 2
        while true {
            let candidate = folder.appendingPathComponent("\(base) \(number)").appendingPathExtension(url.pathExtension)
            if !files.fileExists(atPath: candidate.path) {
                return candidate
            }
            number += 1
        }
    }

    static func time(_ seconds: Double) -> CMTime {
        CMTime(seconds: seconds, preferredTimescale: 600_000)
    }

    /// Encodes the range on its exact bounds (D-108): H.264 and AAC in MP4 at the system's highest quality, the index
    /// at the front. If encoding fails, the samples are copied instead (into an MP4 all the same).
    private static func exportExactVideo(_ request: SegmentExportRequest, to url: URL) async throws {
        do {
            try await run(request, preset: AVAssetExportPresetHighestQuality, type: .mp4, to: url)
        } catch {
            try? FileManager.default.removeItem(at: url)
            try await run(request, preset: AVAssetExportPresetPassthrough, type: .mp4, to: url)
        }
    }

    private static func exportVideo(_ request: SegmentExportRequest, to url: URL) async throws {
        let type: AVFileType = switch fileExtension(for: request) {
        case "mp4": .mp4
        case "m4v": .m4v
        default: .mov
        }
        try await run(request, preset: AVAssetExportPresetPassthrough, type: type, to: url)
    }

    private static func run(_ request: SegmentExportRequest, preset: String, type: AVFileType, to url: URL) async throws {
        let asset = AVURLAsset(url: request.source)
        guard let session = AVAssetExportSession(asset: asset, presetName: preset) else {
            throw SegmentExportError.unsupported
        }
        session.timeRange = CMTimeRange(start: time(request.range.lowerBound), end: time(request.range.upperBound))
        session.shouldOptimizeForNetworkUse = preset != AVAssetExportPresetPassthrough
        if #available(macOS 15, *) {
            try await session.export(to: url, as: type)
        } else {
            session.outputURL = url
            session.outputFileType = type
            await session.export()
            guard session.status == .completed else { throw session.error ?? SegmentExportError.failed }
        }
    }
}
