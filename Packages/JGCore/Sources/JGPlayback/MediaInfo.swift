import AVFoundation
import CoreGraphics

/// What a player needs to know about a file before showing it: playability, duration, the video's display size
/// and the tags of audio files (docs/FEATURES.md §4.2–4.3).
public struct MediaInfo: Equatable, Sendable {
    /// False for containers or codecs AVFoundation cannot play (MKV, WebM, …; DECISIONS D-10).
    public var isPlayable: Bool
    /// Seconds; nil when unknown.
    public var duration: Double?
    /// Display size of the first video track (track transform applied); nil for audio.
    public var videoSize: CGSize?
    public var frameRate: Double?
    public var title: String?
    public var artist: String?
    public var album: String?

    public var hasVideo: Bool {
        videoSize != nil
    }

    public init(
        isPlayable: Bool, duration: Double? = nil, videoSize: CGSize? = nil, frameRate: Double? = nil,
        title: String? = nil, artist: String? = nil, album: String? = nil
    ) {
        self.isPlayable = isPlayable
        self.duration = duration
        self.videoSize = videoSize
        self.frameRate = frameRate
        self.title = title
        self.artist = artist
        self.album = album
    }

    /// Loads the information without decoding media; throws when the file cannot be read at all.
    public static func load(_ asset: AVURLAsset) async throws -> MediaInfo {
        let (playable, duration, metadata) = try await asset.load(.isPlayable, .duration, .commonMetadata)
        guard playable else { return MediaInfo(isPlayable: false) }
        var info = MediaInfo(isPlayable: true, duration: duration.isNumeric ? duration.seconds : nil)
        if let track = try await asset.loadTracks(withMediaType: .video).first {
            let (size, transform, rate) = try await track.load(.naturalSize, .preferredTransform, .nominalFrameRate)
            let display = CGRect(origin: .zero, size: size).applying(transform).size
            info.videoSize = CGSize(width: abs(display.width), height: abs(display.height))
            info.frameRate = rate > 0 ? Double(rate) : nil
        }
        info.title = try await string(metadata, .commonIdentifierTitle)
        info.artist = try await string(metadata, .commonIdentifierArtist)
        info.album = try await string(metadata, .commonIdentifierAlbumName)
        return info
    }

    private static func string(_ metadata: [AVMetadataItem], _ identifier: AVMetadataIdentifier) async throws -> String? {
        guard let item = AVMetadataItem.metadataItems(from: metadata, filteredByIdentifier: identifier).first,
              let value = try await item.load(.stringValue)?.trimmingCharacters(in: .whitespacesAndNewlines),
              !value.isEmpty
        else { return nil }
        return value
    }
}

/// Why an item cannot be played.
public enum PlaybackError: Error, Equatable, Sendable {
    /// AVFoundation does not support the container or codec.
    case unsupported
    /// The file is missing, unreadable or damaged.
    case unreadable
}
