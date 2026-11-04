import Foundation

/// Reaching a pitch or a tempo by speed alone, as on a tape (D-106, W-108): the pitch and the tempo move together,
/// nothing is processed. At most an octave either way.
public enum PlaybackTarget {
    /// The largest distance from a song's own pitch, in semitones.
    public static let limit = 12

    /// The rates a target may take: an octave either way.
    public static let rates: ClosedRange<Double> = 0.5 ... 2

    /// The rate that sounds `semitones` away from the song's own pitch.
    public static func rate(semitones: Double) -> Double {
        clamp(pow(2, semitones / 12))
    }

    /// The rate that takes a song of `songBPM` to `targetBPM`.
    public static func rate(targetBPM: Double, songBPM: Double) -> Double {
        clamp(targetBPM / songBPM)
    }

    /// How many semitones `rate` moves the pitch.
    public static func semitones(rate: Double) -> Double {
        12 * log2(rate)
    }

    /// Whether `semitones` is close enough to a whole number to name a key.
    public static func isWhole(_ semitones: Double) -> Bool {
        abs(semitones - semitones.rounded()) < 0.02
    }

    /// A typed pitch: `5`, `+5`, `-3`, `−3`, `1.5`, `1,5`; kept within `limit`. Nil when unreadable.
    public static func parseSemitones(_ text: String) -> Double? {
        number(text).map { min(max($0, -Double(limit)), Double(limit)) }
    }

    /// A typed tempo: a positive number. Nil when unreadable.
    public static func parseBPM(_ text: String) -> Double? {
        guard let bpm = number(text), bpm > 0, !text.contains("-"), !text.contains("−") else { return nil }
        return bpm
    }

    /// `+2`, `-3`, `+1.6`, `0`.
    public static func label(_ semitones: Double) -> String {
        let rounded = (semitones * 10).rounded() / 10
        let digits = rounded == rounded.rounded() ? String(Int(rounded)) : String(format: "%.1f", rounded)
        return rounded > 0 ? "+" + digits : digits
    }

    private static func clamp(_ rate: Double) -> Double {
        min(max(rate, rates.lowerBound), rates.upperBound)
    }

    private static func number(_ text: String) -> Double? {
        let plain = text.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "−", with: "-")
            .replacingOccurrences(of: ",", with: ".")
        guard !plain.isEmpty, plain.allSatisfy({ $0.isNumber || $0 == "." || $0 == "-" || $0 == "+" }) else { return nil }
        return Double(plain).flatMap { $0.isFinite ? $0 : nil }
    }
}
