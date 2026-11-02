import Foundation

/// Peaks of an audio file for drawing (docs/ARCHITECTURE.md §10): a fixed number of buckets across the whole
/// duration, each with the lowest and highest sample, quantized to a byte (128 = silence).
public struct Waveform: Equatable, Sendable {
    /// Buckets per file, whatever its length.
    public static let bucketCount = 2048

    public let lows: [UInt8]
    public let highs: [UInt8]
    /// Buckets computed so far; the rest are silent until the waveform is complete.
    public let filled: Int
    public let isComplete: Bool

    public init(lows: [UInt8], highs: [UInt8], filled: Int, isComplete: Bool) {
        self.lows = lows
        self.highs = highs
        self.filled = filled
        self.isComplete = isComplete
    }

    public var count: Int {
        lows.count
    }

    /// Lowest sample of bucket `index`, in -1…1.
    public func low(at index: Int) -> Float {
        Self.amplitude(lows[index])
    }

    /// Highest sample of bucket `index`, in -1…1.
    public func high(at index: Int) -> Float {
        Self.amplitude(highs[index])
    }

    static func quantize(_ sample: Float) -> UInt8 {
        UInt8(clamping: Int((min(max(sample, -1), 1) * 127).rounded()) + 128)
    }

    static func amplitude(_ byte: UInt8) -> Float {
        Float(Int(byte) - 128) / 127
    }

    /// Storage form: lows, then highs.
    var data: Data {
        Data(lows + highs)
    }

    init?(data: Data) {
        guard data.count.isMultiple(of: 2), !data.isEmpty else { return nil }
        let bytes = [UInt8](data)
        let half = bytes.count / 2
        self.init(lows: Array(bytes[..<half]), highs: Array(bytes[half...]), filled: half, isComplete: true)
    }
}

/// Peaks of part of a file in -1…1, one pair per bucket across `range` (seconds): a zoomed-in waveform.
public struct WaveformDetail: Equatable, Sendable {
    public let range: ClosedRange<Double>
    public let lows: [Float]
    public let highs: [Float]
}

/// Accumulates mono samples into `Waveform.bucketCount` buckets spread over an expected length; samples beyond
/// the expected length land in the last bucket.
struct WaveformBucketer {
    let bucketCount: Int
    let expectedFrames: Int
    private(set) var lows: [Float]
    private(set) var highs: [Float]
    private(set) var frames = 0

    init(expectedFrames: Int, bucketCount: Int = Waveform.bucketCount) {
        self.bucketCount = max(bucketCount, 1)
        self.expectedFrames = max(expectedFrames, 1)
        lows = Array(repeating: 0, count: self.bucketCount)
        highs = Array(repeating: 0, count: self.bucketCount)
    }

    /// The bucket of sample frame `frame`.
    func bucket(of frame: Int) -> Int {
        min(frame * bucketCount / expectedFrames, bucketCount - 1)
    }

    mutating func append(_ samples: UnsafeBufferPointer<Float>) {
        for sample in samples {
            let index = bucket(of: frames)
            lows[index] = min(lows[index], sample)
            highs[index] = max(highs[index], sample)
            frames += 1
        }
    }

    /// Buckets that will not change any more (all but the one being filled, unless complete).
    func filledBuckets(complete: Bool) -> Int {
        complete ? bucketCount : min(bucket(of: frames), bucketCount)
    }

    func waveform(complete: Bool) -> Waveform {
        Waveform(
            lows: lows.map(Waveform.quantize), highs: highs.map(Waveform.quantize),
            filled: filledBuckets(complete: complete), isComplete: complete
        )
    }
}
