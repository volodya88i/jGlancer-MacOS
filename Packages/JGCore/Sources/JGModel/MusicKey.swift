/// A musical key (D-106, W-107): `tonic` is the pitch class, 0 = C … 11 = B.
public struct MusicKey: Hashable, Sendable {
    public let tonic: Int
    public let isMinor: Bool

    public init(tonic: Int, isMinor: Bool) {
        self.tonic = (tonic % 12 + 12) % 12
        self.isMinor = isMinor
    }

    private static let names = ["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"]

    /// `A min`, `Eb maj`.
    public var label: String {
        "\(Self.names[tonic]) \(isMinor ? "min" : "maj")"
    }

    /// The key `semitones` higher (lower when negative).
    public func shifted(by semitones: Int) -> MusicKey {
        MusicKey(tonic: tonic + semitones, isMinor: isMinor)
    }
}

/// What the analysis found in a song; either part may be missing (silence, no steady beat).
public struct AudioAnalysis: Hashable, Sendable {
    public let bpm: Double?
    public let key: MusicKey?

    public init(bpm: Double?, key: MusicKey?) {
        self.bpm = bpm
        self.key = key
    }

    /// Neither a tempo nor a key.
    public var isEmpty: Bool {
        bpm == nil && key == nil
    }

    /// The tempo as shown: whole beats per minute.
    public var bpmLabel: String? {
        bpm.map { String(Int($0.rounded())) }
    }
}
