import CoreMedia
import Foundation

/// The codecs the app plays from Matroska (decoded by the system) and their CoreMedia format descriptions.
public enum MatroskaCodecs {
    public static let video: Set<String> = ["V_MPEG4/ISO/AVC", "V_MPEGH/ISO/HEVC"]
    public static let audio: Set<String> = [
        "A_AAC", "A_AAC/MPEG4/LC", "A_AAC/MPEG2/LC", "A_AC3", "A_EAC3", "A_MPEG/L3", "A_OPUS",
    ]

    public static func isSupported(_ track: MatroskaTrack) -> Bool {
        guard !track.isEncoded else { return false }
        switch track.kind {
        case .video: return video.contains(track.codecID) && track.codecPrivate != nil
        case .audio: return audio.contains(track.codecID)
        case .other: return false
        }
    }

    /// The format description of a supported track; nil otherwise.
    public static func formatDescription(for track: MatroskaTrack) -> CMFormatDescription? {
        guard isSupported(track) else { return nil }
        return track.kind == .video ? videoFormat(track) : audioFormat(track)
    }

    private static func videoFormat(_ track: MatroskaTrack) -> CMFormatDescription? {
        guard let config = track.codecPrivate else { return nil }
        let (codec, atom): (CMVideoCodecType, String) = track.codecID == "V_MPEGH/ISO/HEVC"
            ? (kCMVideoCodecType_HEVC, "hvcC") : (kCMVideoCodecType_H264, "avcC")
        let extensions = [
            kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms: [atom: config],
        ] as CFDictionary
        var format: CMFormatDescription?
        CMVideoFormatDescriptionCreate(
            allocator: nil, codecType: codec, width: Int32(track.width), height: Int32(track.height),
            extensions: extensions, formatDescriptionOut: &format
        )
        return format
    }

    private static func audioFormat(_ track: MatroskaTrack) -> CMFormatDescription? {
        var description = AudioStreamBasicDescription()
        description.mSampleRate = track.sampleRate > 0 ? track.sampleRate : 48000
        description.mChannelsPerFrame = UInt32(max(track.channels, 1))
        var cookie: Data?
        switch track.codecID {
        case "A_AC3":
            description.mFormatID = kAudioFormatAC3
            description.mFramesPerPacket = 1536
        case "A_EAC3":
            description.mFormatID = kAudioFormatEnhancedAC3
            description.mFramesPerPacket = 1536
        case "A_MPEG/L3":
            description.mFormatID = kAudioFormatMPEGLayer3
            description.mFramesPerPacket = 1152
        case "A_OPUS":
            description.mFormatID = kAudioFormatOpus
            description.mSampleRate = 48000
            description.mFramesPerPacket = 960
            cookie = track.codecPrivate
        default:
            description.mFormatID = kAudioFormatMPEG4AAC
            description.mFramesPerPacket = 1024
            let config = track.codecPrivate ?? lowComplexityConfig(sampleRate: description.mSampleRate, channels: track.channels)
            cookie = esds(audioSpecificConfig: config)
        }
        var format: CMAudioFormatDescription?
        let status = cookie.map { data in
            data.withUnsafeBytes { bytes in
                CMAudioFormatDescriptionCreate(
                    allocator: nil, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: bytes.count,
                    magicCookie: bytes.baseAddress, extensions: nil, formatDescriptionOut: &format
                )
            }
        } ?? CMAudioFormatDescriptionCreate(
            allocator: nil, asbd: &description, layoutSize: 0, layout: nil, magicCookieSize: 0, magicCookie: nil,
            extensions: nil, formatDescriptionOut: &format
        )
        return status == noErr ? format : nil
    }

    /// Frames of audio per packet, for packet timing when blocks carry several.
    public static func samplesPerPacket(_ track: MatroskaTrack) -> Double {
        switch track.codecID {
        case "A_AC3", "A_EAC3": 1536
        case "A_MPEG/L3": 1152
        case "A_OPUS": 960
        default: 1024
        }
    }

    // MARK: AAC configuration

    /// An AudioSpecificConfig for AAC-LC (old "A_AAC/MPEG4/LC" tracks carry none).
    static func lowComplexityConfig(sampleRate: Double, channels: Int) -> Data {
        let rates: [Double] = [96000, 88200, 64000, 48000, 44100, 32000, 24000, 22050, 16000, 12000, 11025, 8000, 7350]
        let index = UInt8(rates.firstIndex(of: sampleRate) ?? 4)
        let objectType: UInt8 = 2
        let channelConfig = UInt8(min(max(channels, 1), 7))
        return Data([objectType << 3 | index >> 1, (index & 1) << 7 | channelConfig << 3])
    }

    /// An MPEG-4 elementary stream descriptor around an AudioSpecificConfig: the magic cookie CoreAudio's AAC decoder
    /// expects.
    public static func esds(audioSpecificConfig config: Data) -> Data {
        func descriptor(_ tag: UInt8, _ body: Data) -> Data {
            Data([tag, 0x80, 0x80, 0x80, UInt8(body.count)]) + body
        }
        let specific = descriptor(0x05, config)
        let decoderConfig = descriptor(0x04, Data([0x40, 0x15, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0]) + specific)
        let slConfig = descriptor(0x06, Data([0x02]))
        return descriptor(0x03, Data([0, 0, 0]) + decoderConfig + slConfig)
    }

    /// The AudioSpecificConfig inside an `esds` magic cookie (or the cookie itself when it already is one).
    public static func audioSpecificConfig(fromCookie cookie: Data) -> Data? {
        let bytes = [UInt8](cookie)
        guard bytes.first == 0x03 else { return cookie }
        var index = 0
        while index < bytes.count {
            let tag = bytes[index]
            index += 1
            var length = 0
            for _ in 0 ..< 4 where index < bytes.count {
                let byte = bytes[index]
                index += 1
                length = length << 7 | Int(byte & 0x7F)
                if byte & 0x80 == 0 {
                    break
                }
            }
            switch tag {
            case 0x03: index += 3
            case 0x04: index += 13
            case 0x05: return index + length <= bytes.count ? Data(bytes[index ..< index + length]) : nil
            default: index += length
            }
        }
        return nil
    }
}
