import Accelerate
import Foundation

/// Finds a song's tempo (D-106, W-107): the strength of note onsets over time, then the beat period that repeats best
/// in it, leaning toward moderate tempos; half or double the true tempo remains possible. Takes 8 kHz mono samples.
public enum TempoDetector {
    private static let window = 512
    private static let envelopeRate = 100.0
    private static let slowestBPM = 60.0
    private static let fastestBPM = 200.0
    private static let preferredBPM = 120.0
    private static let preferenceOctaves = 1.2
    /// Three minutes of envelope at most, from the song's middle.
    private static let longestEnvelope = 18000
    private static let refinedBeats = 8
    private static let compression: Float = 100

    /// Beats per minute, or nil when the samples are too short or have no onsets.
    public static func detect(_ samples: [Float], sampleRate: Double) -> Double? {
        let envelope = envelope(samples, sampleRate: sampleRate)
        let minLag = Int((60 * envelopeRate / fastestBPM).rounded(.down))
        let maxLag = Int((60 * envelopeRate / slowestBPM).rounded(.up))
        guard envelope.count >= maxLag * 4 else { return nil }
        let correlation = autocorrelation(envelope, lags: minLag ..< min(maxLag * refinedBeats + 2, envelope.count))
        var bestLag = 0
        var bestScore = 0.0
        for lag in minLag ... maxLag {
            // A real beat also repeats at two and four beats.
            var score = correlation[lag] + 0.5 * value(correlation, lag * 2) + 0.25 * value(correlation, lag * 4)
            let octaves = log2(60 * envelopeRate / Double(lag) / preferredBPM) / preferenceOctaves
            score *= exp(-0.5 * octaves * octaves)
            if score > bestScore {
                bestScore = score
                bestLag = lag
            }
        }
        guard bestLag > 0 else { return nil }
        return min(max(60 * envelopeRate / refined(correlation, lag: bestLag), slowestBPM), fastestBPM)
    }

    private static func value(_ values: [Double], _ index: Int) -> Double {
        index < values.count ? values[index] : 0
    }

    private static func autocorrelation(_ envelope: [Float], lags: Range<Int>) -> [Double] {
        var correlation = [Double](repeating: 0, count: max(lags.upperBound, 0))
        envelope.withUnsafeBufferPointer { values in
            guard let base = values.baseAddress else { return }
            for lag in lags {
                var sum: Float = 0
                vDSP_dotpr(base + lag, 1, base, 1, &sum, vDSP_Length(values.count - lag))
                correlation[lag] = Double(sum) / Double(values.count - lag)
            }
        }
        return correlation
    }

    /// The period to a fraction of an envelope step: measured over several beats, the error divides by their number.
    private static func refined(_ correlation: [Double], lag: Int) -> Double {
        var period = Double(lag)
        var beats = 2
        while beats <= refinedBeats, (beats + 1) * lag < correlation.count {
            let centre = period * Double(beats)
            let from = Int((centre - Double(beats)).rounded(.down))
            let upTo = min(Int((centre + Double(beats)).rounded(.up)), correlation.count - 2)
            var peak = from
            for index in stride(from: from, through: upTo, by: 1) where correlation[index] > correlation[peak] {
                peak = index
            }
            let (left, middle, right) = (correlation[peak - 1], correlation[peak], correlation[peak + 1])
            let curve = left - 2 * middle + right
            let offset = abs(curve) < 1e-12 ? 0 : 0.5 * (left - right) / curve
            period = (Double(peak) + min(max(offset, -0.5), 0.5)) / Double(beats)
            beats *= 2
        }
        return period
    }

    /// The rise of compressed spectral energy per step, its local average removed, from the song's middle when long.
    private static func envelope(_ samples: [Float], sampleRate: Double) -> [Float] {
        let hop = Int((sampleRate / envelopeRate).rounded())
        guard samples.count >= window + hop, let fft = AudioFFT(size: window) else { return [] }
        let all = (samples.count - window) / hop
        let skip = max(0, all - longestEnvelope) / 2
        let frames = min(all, longestEnvelope)
        var current = [Float](repeating: 0, count: window / 2 + 1)
        var previous = current
        var flux = [Float](repeating: 0, count: frames)
        samples.withUnsafeBufferPointer { buffer in
            for frame in 0 ..< frames {
                fft.magnitudes(buffer, start: (frame + skip) * hop, into: &current)
                var rise: Float = 0
                for bin in current.indices {
                    let level = log(1 + compression * current[bin])
                    if frame > 0, level > previous[bin] {
                        rise += level - previous[bin]
                    }
                    previous[bin] = level
                }
                flux[frame] = rise
            }
        }
        return withoutLocalMean(flux)
    }

    /// Each step's rise above the mean of the half second around it, never below zero.
    private static func withoutLocalMean(_ flux: [Float]) -> [Float] {
        let radius = Int(envelopeRate) / 2
        var envelope = [Float](repeating: 0, count: flux.count)
        var running = 0.0
        for index in flux.indices {
            running += Double(flux[index])
            if index > 2 * radius {
                running -= Double(flux[index - 2 * radius - 1])
            }
            let mean = running / Double(min(index + 1, 2 * radius + 1))
            let centre = max(0, index - radius)
            envelope[centre] = max(0, flux[centre] - Float(mean))
        }
        return envelope
    }
}
