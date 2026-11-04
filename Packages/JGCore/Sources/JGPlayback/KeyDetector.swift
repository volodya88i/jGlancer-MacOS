import Foundation
import JGModel

/// Finds a song's key (D-106, W-107): how much of each of the 12 pitch classes its spectral peaks hold over its whole
/// length, compared with Sha'ath's profiles of all 24 keys (tuned to popular and electronic music). Peaks at their
/// interpolated frequency leave out most of the noise and drums. Takes 8 kHz mono samples.
public enum KeyDetector {
    private static let window = 4096
    private static let hop = 2048
    private static let lowestHz = 65.0
    private static let highestHz = 2000.0
    private static let silentFrame: Float = 0.002

    private static let majorProfile = [6.6, 2, 3.5, 2.3, 4.6, 4, 2.5, 5.2, 2.4, 3.7, 2.3, 3.4]
    private static let minorProfile = [6.5, 2.7, 3.5, 5.4, 2.6, 3.5, 2.5, 5.2, 4, 2.7, 4.3, 3.2]

    /// The key, or nil when the samples are too short or silent.
    public static func detect(_ samples: [Float], sampleRate: Double) -> MusicKey? {
        guard let chroma = chroma(samples, sampleRate: sampleRate) else { return nil }
        var best = MusicKey(tonic: 0, isMinor: false)
        var bestScore = -Double.infinity
        for tonic in 0 ..< 12 {
            for isMinor in [false, true] {
                let score = correlation(chroma, isMinor ? minorProfile : majorProfile, tonic: tonic)
                if score > bestScore {
                    bestScore = score
                    best = MusicKey(tonic: tonic, isMinor: isMinor)
                }
            }
        }
        return best
    }

    private static func chroma(_ samples: [Float], sampleRate: Double) -> [Double]? {
        guard samples.count >= window, let fft = AudioFFT(size: window) else { return nil }
        let bins = max(1, Int(lowestHz * Double(window) / sampleRate)) ... min(
            window / 2 - 1, Int(highestHz * Double(window) / sampleRate) + 1
        )
        var magnitudes = [Float](repeating: 0, count: window / 2 + 1)
        var total = [Double](repeating: 0, count: 12)
        var heard = false
        samples.withUnsafeBufferPointer { buffer in
            for start in stride(from: 0, through: samples.count - window, by: hop) {
                fft.magnitudes(buffer, start: start, into: &magnitudes)
                guard let frame = frameChroma(magnitudes, bins: bins, sampleRate: sampleRate) else { continue }
                // Each moment counts the same: a loud chorus must not decide alone.
                let sum = frame.reduce(0, +)
                for pitch in 0 ..< 12 {
                    total[pitch] += frame[pitch] / sum
                }
                heard = true
            }
        }
        return heard ? total : nil
    }

    /// The pitch classes of one block's spectral peaks, by magnitude; nil for a silent block.
    private static func frameChroma(_ magnitudes: [Float], bins: ClosedRange<Int>, sampleRate: Double) -> [Double]? {
        var frame = [Double](repeating: 0, count: 12)
        var loudest: Float = 0
        for bin in bins {
            let (below, value, above) = (magnitudes[bin - 1], magnitudes[bin], magnitudes[bin + 1])
            loudest = max(loudest, value)
            guard value > below, value >= above else { continue }
            let curve = Double(below - 2 * value + above)
            let offset = curve == 0 ? 0 : 0.5 * Double(below - above) / curve
            let hertz = (Double(bin) + offset) * sampleRate / Double(window)
            let note = Int((12 * log2(hertz / 440)).rounded()) + 9
            frame[(note % 12 + 12) % 12] += Double(value)
        }
        guard loudest >= silentFrame, frame.reduce(0, +) > 0 else { return nil }
        return frame
    }

    private static func correlation(_ chroma: [Double], _ profile: [Double], tonic: Int) -> Double {
        let meanChroma = chroma.reduce(0, +) / 12
        let meanProfile = profile.reduce(0, +) / 12
        var product = 0.0
        var chromaSquares = 0.0
        var profileSquares = 0.0
        for index in 0 ..< 12 {
            let chromaValue = chroma[(index + tonic) % 12] - meanChroma
            let profileValue = profile[index] - meanProfile
            product += chromaValue * profileValue
            chromaSquares += chromaValue * chromaValue
            profileSquares += profileValue * profileValue
        }
        return product / (chromaSquares * profileSquares + .leastNonzeroMagnitude).squareRoot()
    }
}
