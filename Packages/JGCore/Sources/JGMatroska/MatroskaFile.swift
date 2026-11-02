import Foundation

/// One track of a Matroska file.
public struct MatroskaTrack: Equatable, Sendable {
    public enum Kind: Sendable {
        case video, audio, other
    }

    public let number: UInt64
    public let kind: Kind
    /// "V_MPEG4/ISO/AVC", "A_AAC", "A_OPUS", …
    public let codecID: String
    public let codecPrivate: Data?
    public var width = 0
    public var height = 0
    /// The display size when it differs from the pixel size (anamorphic video).
    public var displayWidth: Int?
    public var displayHeight: Int?
    public var sampleRate: Double = 0
    public var channels = 0
    public var bitDepth = 0
    /// Seconds per frame, when the file says so.
    public var defaultDuration: Double?
    /// Samples the decoder outputs before the real start (Opus pre-skip), in seconds.
    public var codecDelay: Double = 0
    /// Content compression or encryption, which the reader does not undo.
    public var isEncoded = false
}

/// A block of one track: its frames (laced frames split), presentation time and keyframe flag.
public struct MatroskaPacket: Sendable {
    public let track: UInt64
    /// Presentation time in seconds.
    public let time: Double
    public let duration: Double?
    public let isKeyframe: Bool
    public let frames: [Data]
}

/// A seek point: the cluster that holds a keyframe at `time`.
public struct MatroskaCue: Equatable, Sendable {
    public let time: Double
    /// Offset of the cluster in the file.
    public let clusterOffset: Int
}

/// Errors reading a Matroska file.
public enum MatroskaError: Error, Sendable {
    case notMatroska
    case damaged
    /// No video or audio track the system can decode.
    case unsupported
}

/// A Matroska (MKV / MKA / WebM) file, memory-mapped: the header, tracks, seek points, and packets read in order
/// from any cluster (docs/DECISIONS.md D-71). Pure parsing; decoding is the system's.
public final class MatroskaFile: @unchecked Sendable {
    public let url: URL
    public private(set) var tracks: [MatroskaTrack] = []
    public private(set) var duration: Double?
    public private(set) var title: String?
    public private(set) var cues: [MatroskaCue] = []
    /// Where the first cluster starts.
    public private(set) var firstCluster: Int?

    /// Nanoseconds per timecode tick.
    private var timecodeScale: Double = 1_000_000
    private var segment: Range<Int> = 0 ..< 0
    // The mapped file; `bytes` points into it for the object's lifetime.
    private let data: Data
    private let reader: EBMLReader

    public init(url: URL) throws {
        self.url = url
        data = try Data(contentsOf: url, options: .alwaysMapped)
        // `Data` keeps the mapping alive; the pointer stays valid as long as `data` is not mutated.
        reader = EBMLReader(bytes: data.withUnsafeBytes { UnsafeRawBufferPointer(start: $0.baseAddress, count: $0.count) })
        try parse()
    }

    private func parse() throws {
        guard let header = reader.element(at: 0, limit: reader.count), header.id == MatroskaID.ebml,
              let segmentElement = reader.element(at: header.end, limit: reader.count), segmentElement.id == MatroskaID.segment
        else { throw MatroskaError.notMatroska }
        segment = segmentElement.payload ..< segmentElement.end
        var offset = segment.lowerBound
        while offset < segment.upperBound, let element = reader.element(at: offset, limit: segment.upperBound) {
            guard visitTopLevel(element, at: offset), !element.hasUnknownSize, element.end > offset else { break }
            offset = element.end
        }
        guard !tracks.isEmpty, firstCluster != nil else { throw MatroskaError.damaged }
        if cues.isEmpty {
            cues = scanClusters()
        }
    }

    /// One child of the segment; false when the header scan can stop (clusters are read on demand).
    private func visitTopLevel(_ element: EBMLElement, at offset: Int) -> Bool {
        switch element.id {
        case MatroskaID.info: parseInfo(element)
        case MatroskaID.tracks: parseTracks(element)
        case MatroskaID.cues: parseCues(element)
        case MatroskaID.cluster:
            firstCluster = firstCluster ?? offset
            // With the seek points known (or a cluster of unknown size) nothing after the clusters is needed.
            return !(element.hasUnknownSize || !cues.isEmpty) || tracks.isEmpty
        default: break
        }
        return true
    }

    private func parseInfo(_ info: EBMLElement) {
        var rawDuration: Double?
        for child in reader.children(info.payload ..< info.end) {
            switch child.id {
            case MatroskaID.timecodeScale: timecodeScale = Double(max(reader.unsigned(child), 1))
            case MatroskaID.duration: rawDuration = reader.float(child)
            case MatroskaID.title: title = reader.string(child)
            default: break
            }
        }
        duration = rawDuration.map { $0 * timecodeScale / 1_000_000_000 }
    }

    private func parseTracks(_ element: EBMLElement) {
        for entry in reader.children(element.payload ..< element.end) where entry.id == MatroskaID.trackEntry {
            if let track = parseTrack(entry) {
                tracks.append(track)
            }
        }
    }

    private func parseTrack(_ entry: EBMLElement) -> MatroskaTrack? {
        var number: UInt64?
        var kind = MatroskaTrack.Kind.other
        var codec = ""
        var codecPrivate: Data?
        var extra: [EBMLElement] = []
        for child in reader.children(entry.payload ..< entry.end) {
            switch child.id {
            case MatroskaID.trackNumber: number = reader.unsigned(child)
            case MatroskaID.trackType: kind = [1: .video, 2: .audio][reader.unsigned(child)] ?? .other
            case MatroskaID.codecID: codec = reader.string(child)
            case MatroskaID.codecPrivate: codecPrivate = reader.data(child.payload ..< child.end)
            default: extra.append(child)
            }
        }
        guard let number else { return nil }
        var track = MatroskaTrack(number: number, kind: kind, codecID: codec, codecPrivate: codecPrivate)
        for child in extra {
            apply(child, to: &track)
        }
        return track
    }

    private func apply(_ child: EBMLElement, to track: inout MatroskaTrack) {
        switch child.id {
        case MatroskaID.defaultDuration: track.defaultDuration = Double(reader.unsigned(child)) / 1_000_000_000
        case MatroskaID.codecDelay: track.codecDelay = Double(reader.unsigned(child)) / 1_000_000_000
        case MatroskaID.contentEncodings: track.isEncoded = true
        case MatroskaID.video: applyVideo(child, to: &track)
        case MatroskaID.audio: applyAudio(child, to: &track)
        default: break
        }
    }

    private func applyVideo(_ element: EBMLElement, to track: inout MatroskaTrack) {
        for item in reader.children(element.payload ..< element.end) {
            let value = Int(reader.unsigned(item))
            switch item.id {
            case MatroskaID.pixelWidth: track.width = value
            case MatroskaID.pixelHeight: track.height = value
            case MatroskaID.displayWidth: track.displayWidth = value
            case MatroskaID.displayHeight: track.displayHeight = value
            default: break
            }
        }
    }

    private func applyAudio(_ element: EBMLElement, to track: inout MatroskaTrack) {
        for item in reader.children(element.payload ..< element.end) {
            switch item.id {
            case MatroskaID.samplingFrequency: track.sampleRate = reader.float(item)
            case MatroskaID.channels: track.channels = Int(reader.unsigned(item))
            case MatroskaID.bitDepth: track.bitDepth = Int(reader.unsigned(item))
            default: break
            }
        }
    }

    private func parseCues(_ element: EBMLElement) {
        var points: [MatroskaCue] = []
        for point in reader.children(element.payload ..< element.end) where point.id == MatroskaID.cuePoint {
            var time: UInt64?
            var position: UInt64?
            for child in reader.children(point.payload ..< point.end) {
                if child.id == MatroskaID.cueTime {
                    time = reader.unsigned(child)
                } else if child.id == MatroskaID.cueTrackPositions, position == nil {
                    position = reader.children(child.payload ..< child.end)
                        .first { $0.id == MatroskaID.cueClusterPosition }.map(reader.unsigned)
                }
            }
            if let time, let position {
                points.append(MatroskaCue(time: seconds(Int64(time)), clusterOffset: segment.lowerBound + Int(position)))
            }
        }
        cues = points.sorted { $0.time < $1.time }
    }

    /// Without Cues: every cluster's start time (cluster headers only; their blocks are skipped).
    private func scanClusters() -> [MatroskaCue] {
        var points: [MatroskaCue] = []
        var offset = firstCluster ?? segment.upperBound
        while offset < segment.upperBound, let element = reader.element(at: offset, limit: segment.upperBound) {
            if element.id == MatroskaID.cluster,
               let timecode = reader.children(element.payload ..< min(element.end, element.payload + 64))
               .first(where: { $0.id == MatroskaID.timecode })
            {
                points.append(MatroskaCue(time: seconds(Int64(reader.unsigned(timecode))), clusterOffset: offset))
            }
            guard !element.hasUnknownSize, element.end > offset else { break }
            offset = element.end
        }
        return points
    }

    func seconds(_ ticks: Int64) -> Double {
        Double(ticks) * timecodeScale / 1_000_000_000
    }

    // MARK: Packets

    /// The cluster to start from to show `time`: the last seek point at or before it.
    public func clusterOffset(before time: Double) -> Int {
        cues.last { $0.time <= time }?.clusterOffset ?? firstCluster ?? segment.lowerBound
    }

    /// Packets in file order from the cluster at `offset`.
    public func packets(from offset: Int) -> MatroskaPacketReader {
        MatroskaPacketReader(file: self, reader: reader, offset: offset, end: segment.upperBound)
    }
}
