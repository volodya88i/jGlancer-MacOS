import Foundation

/// A network that separates one piece of stereo audio (`segmentFrames` frames, planar: left then right) into
/// `sources` stereo sources (planar, source after source): the Core ML model in the app, an identity in the tests.
public protocol StemSeparator: AnyObject {
    var sources: Int { get }
    var segmentFrames: Int { get }
    /// The share of a piece that overlaps the next: Demucs a quarter, RoFormer half.
    var overlap: Double { get }
    /// Whether the network takes the audio normalized by its mono mix (Demucs) or as it is (RoFormer).
    var normalizes: Bool { get }
    /// `input`: 2 × `segmentFrames` samples; `output`: sources × 2 × `segmentFrames` samples.
    func separate(_ input: UnsafeBufferPointer<Float>, into output: UnsafeMutableBufferPointer<Float>) throws
}

public extension StemSeparator {
    var overlap: Double {
        0.25
    }

    var normalizes: Bool {
        true
    }
}

/// Where one stem's audio goes, in order, as it is finished (a WAV file being written).
public protocol StemSink: AnyObject {
    func write(left: ArraySlice<Float>, right: ArraySlice<Float>) throws
}

/// A stem the splitter writes, and where it goes.
public struct StemOutput {
    /// What the stem is made of: one of the network's sources, or the song less one (the instrumental is the song less
    /// the vocals, so the two add up to the song exactly; measured as clean as adding the other three sources, D-130).
    public enum Part: Equatable, Sendable {
        case source(Int)
        case songWithout(Int)

        /// The network's source the part takes.
        public var source: Int {
            switch self {
            case let .source(index), let .songWithout(index): index
            }
        }
    }

    public let part: Part
    public let sink: StemSink

    public init(_ part: Part, to sink: StemSink) {
        self.part = part
        self.sink = sink
    }
}

/// One piece of the song the network runs on.
public struct StemSegment: Equatable, Sendable {
    public let offset: Int
    public let length: Int
}

/// The split was stopped.
public struct StemSplitCancelled: Error {}

/// Splits a song as Demucs' own `apply_model` does (D-97, as Windows W-85): the audio is normalized by its mono mix
/// (when the network wants it), cut into pieces of the model's length overlapping as the network wants (Demucs by a
/// quarter), each piece run through the network (a short last piece gets the audio around it as context, zeros past
/// the ends) and joined with triangular cross-fades. Finished audio goes to the sinks as each piece completes, so a
/// long song never holds its stems in memory at once.
public enum StemSplitter {
    /// The pieces of a song of `frames` frames.
    public static func plan(frames: Int, segment: Int, overlap: Double = 0.25) -> [StemSegment] {
        precondition(segment > 0 && overlap < 1)
        let stride = Int((1 - overlap) * Double(segment))
        return Swift.stride(from: 0, to: frames, by: stride).map { StemSegment(offset: $0, length: min(segment, frames - $0)) }
    }

    /// The cross-fade of a piece: rising to 1 in the middle and falling again (Demucs' transition weight).
    public static func weights(_ segment: Int) -> [Float] {
        let half = segment / 2
        let raw = (0 ..< segment).map { Float($0 < half ? $0 + 1 : segment - $0) }
        let top = raw.max() ?? 1
        return raw.map { $0 / top }
    }

    /// Splits `left` / `right` (at the model's sample rate) and writes `outputs`. `progress` gets the share done after
    /// each piece; `isCancelled` is checked between pieces.
    public static func split(
        left: [Float], right: [Float], separator: StemSeparator, outputs: [StemOutput],
        progress: ((Double) -> Void)? = nil, isCancelled: () -> Bool = { false }
    ) throws {
        let frames = min(left.count, right.count)
        let segment = separator.segmentFrames
        let (mean, deviation) = separator.normalizes ? normalization(left, right, frames) : (0, 1)
        let plan = plan(frames: frames, segment: segment, overlap: separator.overlap)
        var input = [Float](repeating: 0, count: 2 * segment)
        var output = [Float](repeating: 0, count: separator.sources * 2 * segment)
        var joiner = Joiner(outputs: outputs, segment: segment, mean: mean, deviation: deviation)
        var start = 0
        for (index, piece) in plan.enumerated() {
            if isCancelled() {
                throw StemSplitCancelled()
            }
            // A short piece is centred in the network's length with the audio around it (zeros past the ends).
            let pad = (segment - piece.length) / 2
            let from = piece.offset - pad
            for pos in 0 ..< segment {
                let frame = from + pos
                let inside = frame >= 0 && frame < frames
                input[pos] = inside ? (left[frame] - mean) / deviation : 0
                input[segment + pos] = inside ? (right[frame] - mean) / deviation : 0
            }
            try input.withUnsafeBufferPointer { inputBuffer in
                try output.withUnsafeMutableBufferPointer { buffer in
                    buffer.update(repeating: 0)
                    try separator.separate(inputBuffer, into: buffer)
                }
            }
            joiner.add(output, length: piece.length, pad: pad, at: piece.offset - start)
            // Everything before the next piece is final.
            let next = index + 1 < plan.count ? plan[index + 1].offset : frames
            try joiner.flush(next - start, song: left, right, at: start)
            start = next
            progress?(Double(index + 1) / Double(plan.count))
        }
    }

    /// Sums the pieces with their cross-fade weights and hands finished audio to the outputs.
    private struct Joiner {
        let outputs: [StemOutput]
        /// The sources the outputs take, and per source the weighted sums from the first frame not written yet.
        let order: [Int]
        let segment: Int
        let weights: [Float]
        let mean: Float
        let deviation: Float
        var sumsLeft: [[Float]]
        var sumsRight: [[Float]]
        var weightSums: [Float]

        init(outputs: [StemOutput], segment: Int, mean: Float, deviation: Float) {
            self.outputs = outputs
            order = Set(outputs.map(\.part.source)).sorted()
            self.segment = segment
            weights = StemSplitter.weights(segment)
            self.mean = mean
            self.deviation = deviation
            sumsLeft = order.map { _ in [Float](repeating: 0, count: segment) }
            sumsRight = sumsLeft
            weightSums = [Float](repeating: 0, count: segment)
        }

        /// Adds a piece's output (sources × 2 × segment, the audio `pad` frames in) at `shift` frames from the start.
        mutating func add(_ output: [Float], length: Int, pad: Int, at shift: Int) {
            for pos in 0 ..< length {
                weightSums[shift + pos] += weights[pos]
            }
            for (slot, source) in order.enumerated() {
                let baseLeft = source * 2 * segment + pad
                let baseRight = baseLeft + segment
                let weights = weights
                sumsLeft[slot].withUnsafeMutableBufferPointer { sumLeft in
                    sumsRight[slot].withUnsafeMutableBufferPointer { sumRight in
                        for pos in 0 ..< length {
                            sumLeft[shift + pos] += output[baseLeft + pos] * weights[pos]
                            sumRight[shift + pos] += output[baseRight + pos] * weights[pos]
                        }
                    }
                }
            }
        }

        /// Writes the first `done` frames (final now; the song's from frame `start`) and moves the sums along.
        mutating func flush(_ done: Int, song left: [Float], _ right: [Float], at start: Int) throws {
            var finished: [Int: (left: [Float], right: [Float])] = [:]
            for (slot, source) in order.enumerated() {
                var outLeft = [Float](repeating: 0, count: done)
                var outRight = [Float](repeating: 0, count: done)
                for pos in 0 ..< done {
                    outLeft[pos] = sumsLeft[slot][pos] / weightSums[pos] * deviation + mean
                    outRight[pos] = sumsRight[slot][pos] / weightSums[pos] * deviation + mean
                }
                finished[source] = (outLeft, outRight)
                StemSplitter.slide(&sumsLeft[slot], by: done)
                StemSplitter.slide(&sumsRight[slot], by: done)
            }
            StemSplitter.slide(&weightSums, by: done)
            for output in outputs {
                guard let audio = finished[output.part.source] else { continue }
                switch output.part {
                case .source:
                    try output.sink.write(left: audio.left[...], right: audio.right[...])
                case .songWithout:
                    let restLeft = (0 ..< done).map { left[start + $0] - audio.left[$0] }
                    let restRight = (0 ..< done).map { right[start + $0] - audio.right[$0] }
                    try output.sink.write(left: restLeft[...], right: restRight[...])
                }
            }
        }
    }

    /// Demucs normalizes by the mono mix: its mean and (unbiased) standard deviation; silence is not scaled.
    static func normalization(_ left: [Float], _ right: [Float], _ frames: Int) -> (mean: Float, deviation: Float) {
        guard frames > 0 else { return (0, 1) }
        var sum = 0.0
        for pos in 0 ..< frames {
            sum += (Double(left[pos]) + Double(right[pos])) / 2
        }
        let mean = sum / Double(frames)
        var squares = 0.0
        for pos in 0 ..< frames {
            let difference = (Double(left[pos]) + Double(right[pos])) / 2 - mean
            squares += difference * difference
        }
        let deviation = frames > 1 ? (squares / Double(frames - 1)).squareRoot() : 0
        return (Float(mean), deviation > 1e-8 ? Float(deviation) : 1)
    }

    static func slide(_ buffer: inout [Float], by count: Int) {
        guard count < buffer.count else {
            for pos in buffer.indices {
                buffer[pos] = 0
            }
            return
        }
        buffer.removeFirst(count)
        buffer.append(contentsOf: repeatElement(0, count: count))
    }
}

/// A stem written as it is finished: a 24-bit stereo PCM WAVE file whose header gets its lengths when it is completed
/// (D-97). Samples outside -1…1 are clipped.
public final class WaveStemWriter: StemSink {
    private static let headerSize = 44
    private let handle: FileHandle
    private let sampleRate: Int
    private var dataBytes = 0

    /// Creates (or replaces) the file at `url`.
    public init(url: URL, sampleRate: Int) throws {
        FileManager.default.createFile(atPath: url.path, contents: nil)
        handle = try FileHandle(forWritingTo: url)
        self.sampleRate = sampleRate
        try handle.write(contentsOf: header(dataBytes: 0))
    }

    public func write(left: ArraySlice<Float>, right: ArraySlice<Float>) throws {
        let frames = min(left.count, right.count)
        var bytes = [UInt8](repeating: 0, count: frames * 6)
        var cursor = 0
        for (sampleLeft, sampleRight) in zip(left, right) {
            Self.put(sampleLeft, into: &bytes, at: cursor)
            Self.put(sampleRight, into: &bytes, at: cursor + 3)
            cursor += 6
        }
        try handle.write(contentsOf: bytes)
        dataBytes += bytes.count
    }

    /// Writes the final lengths into the header and closes the file.
    public func complete() throws {
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: header(dataBytes: dataBytes))
        try handle.close()
    }

    /// Closes without completing (a stopped or failed split removes the file).
    public func abandon() {
        try? handle.close()
    }

    private static func put(_ sample: Float, into bytes: inout [UInt8], at index: Int) {
        let value = Int32((min(max(sample, -1), 1) * 8_388_607).rounded())
        bytes[index] = UInt8(truncatingIfNeeded: value)
        bytes[index + 1] = UInt8(truncatingIfNeeded: value >> 8)
        bytes[index + 2] = UInt8(truncatingIfNeeded: value >> 16)
    }

    private func header(dataBytes: Int) -> Data {
        var data = Data()
        func append32(_ value: Int) {
            withUnsafeBytes(of: UInt32(clamping: value).littleEndian) { data.append(contentsOf: $0) }
        }
        func append16(_ value: Int) {
            withUnsafeBytes(of: UInt16(clamping: value).littleEndian) { data.append(contentsOf: $0) }
        }
        data.append(contentsOf: Array("RIFF".utf8))
        append32(dataBytes + Self.headerSize - 8)
        data.append(contentsOf: Array("WAVEfmt ".utf8))
        append32(16)
        append16(1)
        append16(2)
        append32(sampleRate)
        append32(sampleRate * 6)
        append16(6)
        append16(24)
        data.append(contentsOf: Array("data".utf8))
        append32(dataBytes)
        return data
    }
}
