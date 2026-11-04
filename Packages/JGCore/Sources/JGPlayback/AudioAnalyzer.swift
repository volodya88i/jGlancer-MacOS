import AVFoundation
import JGModel

/// Tempo and key of a song (D-106): decoded to 8 kHz mono, as the waveform is, then `TempoDetector` and
/// `KeyDetector`. About a second for a four-minute song.
public enum AudioAnalyzer {
    /// The rate the detectors take.
    public static let sampleRate = 8000.0
    /// Longer files are read up to here: enough for a tempo and a key, and memory stays small (29 MB).
    static let longestSeconds = 15.0 * 60

    /// What the file holds, or nil when it has no readable audio or nothing was found. Cancellable.
    public static func analyze(_ url: URL) async -> AudioAnalysis? {
        guard let samples = try? await samples(of: url), !Task.isCancelled else { return nil }
        let analysis = AudioAnalysis(
            bpm: TempoDetector.detect(samples, sampleRate: sampleRate), key: KeyDetector.detect(samples, sampleRate: sampleRate)
        )
        return analysis.isEmpty ? nil : analysis
    }

    /// Mono `sampleRate` float samples of the first audio track; nil without audio or when cancelled.
    static func samples(of url: URL) async throws -> [Float]? {
        let asset = AVURLAsset(url: url)
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return nil }
        let reader = try AVAssetReader(asset: asset)
        reader.timeRange = CMTimeRange(start: .zero, duration: CMTime(seconds: longestSeconds, preferredTimescale: 1))
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
                return nil
            }
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            let start = samples.count
            samples.append(contentsOf: repeatElement(0, count: CMBlockBufferGetDataLength(block) / MemoryLayout<Float>.size))
            let status = samples.withUnsafeMutableBytes { bytes -> OSStatus in
                guard let base = bytes.baseAddress else { return kCMBlockBufferBadPointerParameterErr }
                let offset = start * MemoryLayout<Float>.size
                return CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: bytes.count - offset, destination: base + offset)
            }
            if status != kCMBlockBufferNoErr {
                samples.removeSubrange(start...)
            }
        }
        guard reader.status == .completed else { throw reader.error ?? CocoaError(.fileReadCorruptFile) }
        return samples
    }
}
