import AVFoundation
import Foundation
import ImageIO
import JGModel

/// The extended facts of one file for Get Info and, if turned on, the preview pane (docs/FEATURES.md §12): camera
/// and exposure of photos, codecs and rates of video and audio. Read from the file on request, never stored.
/// Values are raw (seconds, bits per second, degrees); the app formats and labels them.
public struct MediaDetails: Equatable, Sendable {
    // Photo
    public var camera: String?
    public var lens: String?
    /// Millimeters.
    public var focalLength: Double?
    /// The f-number.
    public var aperture: Double?
    /// Seconds.
    public var exposureTime: Double?
    public var iso: Int?
    public var latitude: Double?
    public var longitude: Double?
    /// Meters above sea level.
    public var altitude: Double?
    public var colorProfile: String?
    public var bitDepth: Int?
    // Video and audio
    public var videoCodec: String?
    public var frameRate: Double?
    /// Bits per second.
    public var videoBitrate: Double?
    public var audioCodec: String?
    public var audioBitrate: Double?
    /// Hertz.
    public var sampleRate: Double?
    public var channels: Int?

    public init() {}

    /// True when nothing was found.
    public var isEmpty: Bool {
        self == MediaDetails()
    }

    /// Reads the details of `url` (a photo's properties without decoding pixels, or the media tracks).
    public static func read(_ url: URL, kind: MediaKind) async -> MediaDetails {
        switch kind {
        case .photo: await Task.detached(priority: .userInitiated) { photo(url) }.value
        case .video, .audio: await audiovisual(url)
        }
    }

    static func photo(_ url: URL) -> MediaDetails {
        var details = MediaDetails()
        guard let source = CGImageSourceCreateWithURL(url as CFURL, [kCGImageSourceShouldCache: false] as CFDictionary),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        else { return details }
        let tiff = properties[kCGImagePropertyTIFFDictionary] as? [CFString: Any] ?? [:]
        let exif = properties[kCGImagePropertyExifDictionary] as? [CFString: Any] ?? [:]
        details.camera = cameraName(make: tiff[kCGImagePropertyTIFFMake] as? String, model: tiff[kCGImagePropertyTIFFModel] as? String)
        details.lens = (exif[kCGImagePropertyExifLensModel] as? String)?.trimmingCharacters(in: .whitespaces)
        details.focalLength = exif[kCGImagePropertyExifFocalLength] as? Double
        details.aperture = exif[kCGImagePropertyExifFNumber] as? Double
        details.exposureTime = exif[kCGImagePropertyExifExposureTime] as? Double
        details.iso = (exif[kCGImagePropertyExifISOSpeedRatings] as? [Int])?.first
        details.colorProfile = properties[kCGImagePropertyProfileName] as? String
        details.bitDepth = properties[kCGImagePropertyDepth] as? Int
        if let gps = properties[kCGImagePropertyGPSDictionary] as? [CFString: Any] {
            details.latitude = signed(
                gps[kCGImagePropertyGPSLatitude] as? Double,
                ref: gps[kCGImagePropertyGPSLatitudeRef] as? String,
                negative: "S"
            )
            details.longitude = signed(
                gps[kCGImagePropertyGPSLongitude] as? Double,
                ref: gps[kCGImagePropertyGPSLongitudeRef] as? String,
                negative: "W"
            )
            let below = (gps[kCGImagePropertyGPSAltitudeRef] as? Int) == 1
            details.altitude = (gps[kCGImagePropertyGPSAltitude] as? Double).map { below ? -$0 : $0 }
        }
        return details
    }

    /// "Apple iPhone 15 Pro" from make "Apple" and model "iPhone 15 Pro"; a model that already names the maker
    /// ("Canon EOS R5") is used as it is.
    static func cameraName(make: String?, model: String?) -> String? {
        let make = make?.trimmingCharacters(in: .whitespaces) ?? ""
        let model = model?.trimmingCharacters(in: .whitespaces) ?? ""
        if model.isEmpty {
            return make.isEmpty ? nil : make
        }
        if make.isEmpty || model.lowercased().hasPrefix(make.lowercased().split(separator: " ").first.map(String.init) ?? "") {
            return model
        }
        return make + " " + model
    }

    private static func signed(_ value: Double?, ref: String?, negative: String) -> Double? {
        value.map { ref?.uppercased() == negative ? -$0 : $0 }
    }

    static func audiovisual(_ url: URL) async -> MediaDetails {
        var details = MediaDetails()
        let asset = AVURLAsset(url: url)
        if let video = try? await asset.loadTracks(withMediaType: .video).first,
           let (formats, rate, dataRate) = try? await video.load(.formatDescriptions, .nominalFrameRate, .estimatedDataRate)
        {
            details.videoCodec = formats.first.map(codecName)
            details.frameRate = rate > 0 ? Double(rate) : nil
            details.videoBitrate = dataRate > 0 ? Double(dataRate) : nil
        }
        if let audio = try? await asset.loadTracks(withMediaType: .audio).first,
           let (formats, dataRate) = try? await audio.load(.formatDescriptions, .estimatedDataRate)
        {
            details.audioCodec = formats.first.map(codecName)
            details.audioBitrate = dataRate > 0 ? Double(dataRate) : nil
            if let format = formats.first, let stream = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee {
                details.sampleRate = stream.mSampleRate > 0 ? stream.mSampleRate : nil
                details.channels = stream.mChannelsPerFrame > 0 ? Int(stream.mChannelsPerFrame) : nil
                if stream.mBitsPerChannel > 0 {
                    details.bitDepth = Int(stream.mBitsPerChannel)
                }
            }
        }
        return details
    }

    /// A codec's common name from its four-character code ("avc1" → "H.264"); unknown codes as they are.
    static func codecName(_ format: CMFormatDescription) -> String {
        let code = MetadataExtractor.fourCharacterCode(format)
        return codecNames[code] ?? code
    }

    static let codecNames: [String: String] = [
        "avc1": "H.264", "avc3": "H.264", "hvc1": "HEVC", "hev1": "HEVC", "av01": "AV1", "vp09": "VP9",
        "apch": "ProRes 422 HQ", "apcn": "ProRes 422", "apcs": "ProRes 422 LT", "apco": "ProRes 422 Proxy",
        "ap4h": "ProRes 4444", "ap4x": "ProRes 4444 XQ", "jpeg": "Motion JPEG", "mp4v": "MPEG-4",
        "aac": "AAC", "mp4a": "AAC", "alac": "ALAC", ".mp3": "MP3", "flac": "FLAC", "opus": "Opus", "lpcm": "PCM",
        "ac-3": "AC-3", "ec-3": "E-AC-3", "sowt": "PCM", "twos": "PCM",
    ]
}
