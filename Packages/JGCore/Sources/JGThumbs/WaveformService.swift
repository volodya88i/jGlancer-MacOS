import AVFoundation
import Foundation

/// What to draw a waveform of. Library assets (with id and modification date) are cached in `cache.sqlite`;
/// other files only in memory.
public struct WaveformRequest: Hashable, Sendable {
    public let url: URL
    public let assetID: Int64?
    public let modifiedAt: Date?

    public init(url: URL, assetID: Int64?, modifiedAt: Date?) {
        self.url = url
        self.assetID = assetID
        self.modifiedAt = modifiedAt
    }

    var modifiedMilliseconds: Int64? {
        modifiedAt.map { Int64(($0.timeIntervalSince1970 * 1000).rounded()) }
    }
}

/// Waveforms for the audio player (docs/ARCHITECTURE.md §10): decoded at low priority, published progressively
/// while decoding, cached in memory and (for library assets) on disk. Cancelling the consumer stops decoding.
public actor WaveformService {
    private let disk: ThumbnailDiskCache?
    private var memory: [MemoryKey: Waveform] = [:]
    private var recency: [MemoryKey] = []
    /// Waveforms kept in memory (4 KB each).
    private static let memoryCapacity = 64

    private struct MemoryKey: Hashable {
        let path: String
        let modifiedAt: Int64?
    }

    public init(disk: ThumbnailDiskCache?) {
        self.disk = disk
    }

    /// Partial waveforms while decoding, then the complete one; finishes without a value when the file has
    /// no audio or cannot be read.
    public nonisolated func waveform(for request: WaveformRequest) -> AsyncStream<Waveform> {
        AsyncStream { continuation in
            let task = Task(priority: .utility) {
                if let cached = await self.cached(request) {
                    continuation.yield(cached)
                } else if let waveform = try? await WaveformReader.read(request.url, progress: { continuation.yield($0) }),
                          !Task.isCancelled
                {
                    continuation.yield(waveform)
                    await self.remember(waveform, for: request)
                }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Finer peaks of part of the file (`range` in seconds, `bucketCount` buckets), for a zoomed-in waveform.
    /// Read on demand and not cached: a window of a few seconds decodes in milliseconds.
    public nonisolated func detail(for url: URL, range: ClosedRange<Double>, bucketCount: Int) async -> WaveformDetail? {
        try? await WaveformReader.detail(url, range: range, bucketCount: bucketCount)
    }

    private func cached(_ request: WaveformRequest) async -> Waveform? {
        let key = MemoryKey(path: request.url.path, modifiedAt: request.modifiedMilliseconds)
        if let found = memory[key] {
            touch(key)
            return found
        }
        guard let assetID = request.assetID, let modifiedAt = request.modifiedMilliseconds,
              let stored = try? await disk?.waveform(assetID: assetID, modifiedAt: modifiedAt)
        else { return nil }
        insert(stored, for: key)
        return stored
    }

    private func remember(_ waveform: Waveform, for request: WaveformRequest) async {
        insert(waveform, for: MemoryKey(path: request.url.path, modifiedAt: request.modifiedMilliseconds))
        if let assetID = request.assetID, let modifiedAt = request.modifiedMilliseconds {
            try? await disk?.storeWaveform(waveform, assetID: assetID, modifiedAt: modifiedAt)
        }
    }

    private func insert(_ waveform: Waveform, for key: MemoryKey) {
        memory[key] = waveform
        touch(key)
        if recency.count > Self.memoryCapacity {
            memory[recency.removeFirst()] = nil
        }
    }

    private func touch(_ key: MemoryKey) {
        recency.removeAll { $0 == key }
        recency.append(key)
    }
}

/// Decodes the first audio track to mono 8 kHz float samples (the decoder downmixes and resamples) and buckets
/// them into a `Waveform`.
enum WaveformReader {
    static let sampleRate = 8000.0
    /// Partial results are published every this many newly filled buckets.
    static let progressStep = Waveform.bucketCount / 16

    static func read(_ url: URL, progress: (Waveform) -> Void) async throws -> Waveform? {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration)
        var bucketer = WaveformBucketer(expectedFrames: Int((duration.seconds.isFinite ? duration.seconds : 0) * sampleRate))
        var reported = 0
        let read = try await samples(of: asset, in: nil) { samples in
            bucketer.append(samples)
            let filled = bucketer.filledBuckets(complete: false)
            if filled - reported >= progressStep {
                reported = filled
                progress(bucketer.waveform(complete: false))
            }
        }
        return read ? bucketer.waveform(complete: true) : nil
    }

    /// Peaks of `range` only, in floats (no quantization: zoomed in, every level shows).
    static func detail(_ url: URL, range: ClosedRange<Double>, bucketCount: Int) async throws -> WaveformDetail? {
        let length = range.upperBound - range.lowerBound
        guard length > 0, bucketCount > 0 else { return nil }
        var bucketer = WaveformBucketer(expectedFrames: Int(length * sampleRate), bucketCount: bucketCount)
        let read = try await samples(of: AVURLAsset(url: url), in: range) { bucketer.append($0) }
        return read ? WaveformDetail(range: range, lows: bucketer.lows, highs: bucketer.highs) : nil
    }

    /// Mono `sampleRate` float samples of the first audio track (of `range` when given), chunk by chunk.
    /// False when the file has no audio or reading was cancelled.
    private static func samples(
        of asset: AVURLAsset, in range: ClosedRange<Double>?, _ body: (UnsafeBufferPointer<Float>) -> Void
    ) async throws -> Bool {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return false }
        let reader = try AVAssetReader(asset: asset)
        if let range {
            reader.timeRange = CMTimeRange(
                start: CMTime(seconds: range.lowerBound, preferredTimescale: 48000),
                end: CMTime(seconds: range.upperBound, preferredTimescale: 48000)
            )
        }
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1, AVSampleRateKey: sampleRate,
        ])
        output.alwaysCopiesSampleData = false
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? CocoaError(.fileReadUnknown) }
        var samples: [Float] = []
        while let buffer = output.copyNextSampleBuffer() {
            if Task.isCancelled {
                reader.cancelReading()
                return false
            }
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let count = CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size
            samples.removeAll(keepingCapacity: true)
            samples.append(contentsOf: repeatElement(0, count: count))
            let status = samples.withUnsafeMutableBytes { bytes -> OSStatus in
                guard let base = bytes.baseAddress else { return kCMBlockBufferBadPointerParameterErr }
                return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes.count, destination: base)
            }
            guard status == kCMBlockBufferNoErr else { continue }
            samples.withUnsafeBufferPointer(body)
        }
        guard reader.status == .completed else { throw reader.error ?? CocoaError(.fileReadCorruptFile) }
        return true
    }
}
