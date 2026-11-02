import AVFoundation
import Foundation

/// Writes small Matroska files from real H.264 and AAC samples, for tests (the app only reads Matroska).
public enum MatroskaTestWriter {
    /// One sample of a track.
    public struct Sample {
        public let time: Double
        public let data: Data
        public let isKeyframe: Bool
    }

    /// A track to write.
    public struct Track {
        public let codecID: String
        public let codecPrivate: Data?
        public let isVideo: Bool
        public let width: Int
        public let height: Int
        public let sampleRate: Double
        public let channels: Int
        public let samples: [Sample]
    }

    /// Lacing of audio blocks: none, Xiph, fixed or EBML (four frames per block when laced).
    public enum Lacing: UInt8, Sendable {
        case none = 0, xiph = 1, fixed = 2, ebml = 3
    }

    /// The H.264 frames of a movie file and its avcC, read without decoding.
    public static func videoTrack(from url: URL) async throws -> Track {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .video).first else { throw CocoaError(.fileReadUnknown) }
        let format = try await track.load(.formatDescriptions).first
        let atoms = format.flatMap { CMFormatDescriptionGetExtension(
            $0,
            extensionKey: kCMFormatDescriptionExtension_SampleDescriptionExtensionAtoms
        ) }
            as? [String: Any]
        let size = try await track.load(.naturalSize)
        return try Track(
            codecID: "V_MPEG4/ISO/AVC", codecPrivate: atoms?["avcC"] as? Data, isVideo: true,
            width: Int(size.width), height: Int(size.height), sampleRate: 0, channels: 0, samples: samples(of: track, in: asset)
        )
    }

    /// The AAC frames of an audio file and its AudioSpecificConfig.
    public static func audioTrack(from url: URL, audioSpecificConfig: (Data) -> Data?) async throws -> Track {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { throw CocoaError(.fileReadUnknown) }
        guard let format = try await track.load(.formatDescriptions).first,
              let stream = CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee
        else { throw CocoaError(.fileReadUnknown) }
        var cookieSize = 0
        let cookie = CMAudioFormatDescriptionGetMagicCookie(format, sizeOut: &cookieSize).map { Data(bytes: $0, count: cookieSize) }
        return try Track(
            codecID: "A_AAC", codecPrivate: cookie.flatMap(audioSpecificConfig), isVideo: false, width: 0, height: 0,
            sampleRate: stream.mSampleRate, channels: Int(stream.mChannelsPerFrame), samples: samples(of: track, in: asset)
        )
    }

    private static func samples(of track: AVAssetTrack, in asset: AVURLAsset) throws -> [Sample] {
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: nil)
        reader.add(output)
        reader.startReading()
        var result: [Sample] = []
        while let buffer = output.copyNextSampleBuffer() {
            let count = CMSampleBufferGetNumSamples(buffer)
            guard let block = CMSampleBufferGetDataBuffer(buffer), count > 0 else { continue }
            var sizes = [Int](repeating: 0, count: count)
            var used = 0
            CMSampleBufferGetSampleSizeArray(buffer, entryCount: count, arrayToFill: &sizes, entriesNeededOut: &used)
            var timings = [CMSampleTimingInfo](repeating: CMSampleTimingInfo(), count: count)
            var timingCount = 0
            CMSampleBufferGetSampleTimingInfoArray(buffer, entryCount: count, arrayToFill: &timings, entriesNeededOut: &timingCount)
            let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false) as? [[CFString: Any]]
            var offset = 0
            for index in 0 ..< count {
                let size = used == 1 ? sizes[0] : sizes[index]
                var bytes = Data(count: size)
                bytes.withUnsafeMutableBytes { buffer in
                    if let base = buffer.baseAddress {
                        CMBlockBufferCopyDataBytes(block, atOffset: offset, dataLength: size, destination: base)
                    }
                }
                offset += size
                let timing = timingCount == 1 ? timings[0] : timings[index]
                let time = timingCount == 1
                    ? timing.presentationTimeStamp.seconds + Double(index) * timing.duration.seconds
                    : timing.presentationTimeStamp.seconds
                let notSync = attachments.flatMap { index < $0.count ? $0[index][kCMSampleAttachmentKey_NotSync] as? Bool : nil } ?? false
                result.append(Sample(time: time, data: bytes, isKeyframe: !notSync))
            }
        }
        return result
    }

    /// Writes `tracks` to `url`: one cluster per second, SimpleBlocks (audio laced as asked), Cues unless `cues` is false.
    public static func write(_ tracks: [Track], to url: URL, lacing: Lacing = .none, cues: Bool = true, title: String? = nil) throws {
        let duration = tracks.flatMap(\.samples).map(\.time).max() ?? 0
        var info = element(0x2AD7B1, uint(1_000_000)) + element(0x4489, float(duration * 1000))
        if let title {
            info += element(0x7BA9, Data(title.utf8))
        }
        let header = element(0x1549_A966, info) + element(0x1654_AE6B, trackEntries(tracks))
        let (clusters, cuePoints) = clustersAndCues(blocks(tracks, lacing: lacing), duration: duration, base: header.count)
        var segment = header + clusters
        if cues {
            segment += element(0x1C53_BB6B, cuePoints)
        }
        let ebml = element(0x1A45_DFA3, element(0x4282, Data("matroska".utf8)))
        try (ebml + element(0x1853_8067, segment)).write(to: url)
    }

    private struct Block {
        let cluster: Int
        let data: Data
    }

    private static func trackEntries(_ tracks: [Track]) -> Data {
        var entries = Data()
        for (index, track) in tracks.enumerated() {
            var entry = element(0xD7, uint(UInt64(index + 1))) + element(0x83, uint(track.isVideo ? 1 : 2))
                + element(0x86, Data(track.codecID.utf8))
            if let codecPrivate = track.codecPrivate {
                entry += element(0x63A2, codecPrivate)
            }
            entry += track.isVideo
                ? element(0xE0, element(0xB0, uint(UInt64(track.width))) + element(0xBA, uint(UInt64(track.height))))
                : element(0xE1, element(0xB5, float(track.sampleRate)) + element(0x9F, uint(UInt64(track.channels))))
            entries += element(0xAE, entry)
        }
        return entries
    }

    /// Each track keeps its decode order (B-frames); its clusters never go back in time.
    private static func blocks(_ tracks: [Track], lacing: Lacing) -> [Block] {
        var blocks: [Block] = []
        for (index, track) in tracks.enumerated() {
            let number = UInt8(index + 1)
            var cluster = 0
            let laced = !track.isVideo && lacing != .none
            for start in stride(from: 0, to: track.samples.count, by: laced ? 4 : 1) {
                let group = Array(track.samples[start ..< min(start + (laced ? 4 : 1), track.samples.count)])
                let longest = group.map(\.data.count).max() ?? 0
                let frames = lacing == .fixed && laced ? group.map { padded($0.data, to: longest) } : group.map(\.data)
                cluster = max(cluster, Int(group[0].time))
                let spec = BlockSpec(
                    track: number, relative: group[0].time - Double(cluster), keyframe: laced || group[0].isKeyframe,
                    lacing: laced ? lacing : .none
                )
                blocks.append(Block(cluster: cluster, data: simpleBlock(spec, frames: frames)))
            }
        }
        return blocks
    }

    private static func clustersAndCues(_ blocks: [Block], duration: Double, base: Int) -> (Data, Data) {
        var clusters = Data()
        var cuePoints = Data()
        for second in 0 ... Int(duration) {
            let inCluster = blocks.filter { $0.cluster == second }
            guard !inCluster.isEmpty else { continue }
            let body = element(0xE7, uint(UInt64(second * 1000))) + inCluster.reduce(Data()) { $0 + $1.data }
            cuePoints += element(0xBB, element(0xB3, uint(UInt64(second * 1000)))
                + element(0xB7, element(0xF7, uint(1)) + element(0xF1, uint(UInt64(base + clusters.count)))))
            clusters += element(0x1F43_B675, body)
        }
        return (clusters, cuePoints)
    }

    private struct BlockSpec {
        let track: UInt8
        /// Seconds after the cluster's start.
        let relative: Double
        let keyframe: Bool
        let lacing: Lacing
    }

    private static func padded(_ data: Data, to size: Int) -> Data {
        data + Data(count: max(size - data.count, 0))
    }

    private static func simpleBlock(_ spec: BlockSpec, frames: [Data]) -> Data {
        let relative = UInt16(bitPattern: Int16((spec.relative * 1000).rounded()))
        let track = spec.track
        let lacing = spec.lacing
        let keyframe = spec.keyframe
        var body = Data([0x80 | track]) + Data([UInt8(relative >> 8), UInt8(relative & 0xFF)])
        body.append((keyframe ? 0x80 : 0) | lacing.rawValue << 1)
        if lacing != .none {
            body.append(UInt8(frames.count - 1))
            switch lacing {
            case .xiph:
                for frame in frames.dropLast() {
                    body += Data(repeating: 255, count: frame.count / 255) + Data([UInt8(frame.count % 255)])
                }
            case .ebml where frames.count > 1:
                body += vint(UInt64(frames[0].count))
                var previous = frames[0].count
                for frame in frames.dropFirst().dropLast() {
                    let delta = frame.count - previous
                    body += signedVint(delta)
                    previous = frame.count
                }
            default:
                break
            }
        }
        frames.forEach { body += $0 }
        return element(0xA3, body)
    }

    private static func element(_ id: UInt32, _ payload: Data) -> Data {
        var idBytes = withUnsafeBytes(of: id.bigEndian) { Data($0) }
        while idBytes.first == 0 {
            idBytes.removeFirst()
        }
        var size = Data([0x01]) + withUnsafeBytes(of: UInt64(payload.count).bigEndian) { Data($0) }.dropFirst()
        size[size.startIndex] = 0x01
        return idBytes + size + payload
    }

    private static func vint(_ value: UInt64) -> Data {
        // Two bytes are enough for the sizes in tests.
        Data([0x40 | UInt8(value >> 8), UInt8(value & 0xFF)])
    }

    private static func signedVint(_ value: Int) -> Data {
        vint(UInt64(value + (1 << 13) - 1))
    }

    private static func uint(_ value: UInt64) -> Data {
        withUnsafeBytes(of: value.bigEndian) { Data($0) }
    }

    private static func float(_ value: Double) -> Data {
        withUnsafeBytes(of: value.bitPattern.bigEndian) { Data($0) }
    }
}
