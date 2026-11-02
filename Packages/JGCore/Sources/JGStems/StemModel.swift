import Foundation

/// A part of a song that the splitter writes as its own file (D-94, D-97; Windows W-85).
public enum StemKind: String, CaseIterable, Codable, Sendable {
    case vocals = "Vocals"
    case drums = "Drums"
    case bass = "Bass"
    case guitar = "Guitar"
    case piano = "Piano"
    case other = "Other"
}

/// 4 stems (vocals, drums, bass, the rest) or 6 (also guitar and piano).
public enum StemMode: String, CaseIterable, Codable, Sendable {
    case four
    case six
}

/// One Demucs model as the app uses it: its name, the order of the sources it produces (Demucs' own order), its sample
/// rate and the length of the piece of audio it takes at once (D-97). `isFull`: the weights at full precision; otherwise
/// compact: half-precision weights computing at full precision, half the size on disk, inaudibly different (D-103, W-92).
public struct StemModelInfo: Hashable, Sendable {
    public let mode: StemMode
    /// The compiled Core ML model folder in the app's models folder.
    public let name: String
    public let sources: [StemKind]
    public let sampleRate: Int
    public let segmentFrames: Int
    public let isFull: Bool

    private static let fourSources: [StemKind] = [.drums, .bass, .other, .vocals]
    private static let sixSources: [StemKind] = [.drums, .bass, .other, .vocals, .guitar, .piano]

    private static func make(_ mode: StemMode, _ name: String, full: Bool) -> StemModelInfo {
        StemModelInfo(
            mode: mode, name: name, sources: mode == .six ? sixSources : fourSources, sampleRate: 44100, segmentFrames: 343_980,
            isFull: full
        )
    }

    /// Demucs v4 Hybrid Transformer, 4 sources (htdemucs).
    public static let four = make(.four, "htdemucs", full: true)
    /// Demucs v4 Hybrid Transformer, 6 sources (htdemucs_6s).
    public static let six = make(.six, "htdemucs_6s", full: true)
    public static let fourCompact = make(.four, "htdemucs-compact", full: false)
    public static let sixCompact = make(.six, "htdemucs_6s-compact", full: false)

    public static let all = [four, six, fourCompact, sixCompact]

    public static func model(for mode: StemMode, full: Bool = true) -> StemModelInfo {
        switch (mode, full) {
        case (.four, true): four
        case (.six, true): six
        case (.four, false): fourCompact
        case (.six, false): sixCompact
        }
    }

    /// The stems of a mode in the order the window lists them.
    public static func shown(_ mode: StemMode) -> [StemKind] {
        mode == .six ? [.vocals, .drums, .bass, .guitar, .piano, .other] : [.vocals, .drums, .bass, .other]
    }
}

/// The split window's choice: the mode and the stems ticked (remembered between uses, not the folder). At least one
/// stem of the mode stays ticked.
public struct StemChoice: Hashable, Codable, Sendable {
    public private(set) var mode: StemMode
    public private(set) var ticked: Set<StemKind>

    public init(mode: StemMode = .four, ticked: Set<StemKind>? = nil) {
        self.mode = mode
        self.ticked = ticked ?? Set(StemModelInfo.shown(mode))
    }

    /// The ticked stems of the mode, in the window's order.
    public var stems: [StemKind] {
        StemModelInfo.shown(mode).filter(ticked.contains)
    }

    public var canSplit: Bool {
        !stems.isEmpty
    }

    /// Another mode: the stems both modes have keep their ticks; the new mode's own stems (guitar, piano) come ticked,
    /// and so does everything when nothing would be left ticked.
    public func with(mode newMode: StemMode) -> StemChoice {
        guard newMode != mode else { return self }
        let old = Set(StemModelInfo.shown(mode))
        let kept = StemModelInfo.shown(newMode).filter { !old.contains($0) || ticked.contains($0) }
        return StemChoice(mode: newMode, ticked: kept.isEmpty ? Set(StemModelInfo.shown(newMode)) : Set(kept))
    }

    /// Ticks or unticks a stem; the last ticked one stays ticked.
    public func with(_ stem: StemKind, ticked isTicked: Bool) -> StemChoice {
        var copy = self
        if isTicked {
            copy.ticked.insert(stem)
        } else {
            copy.ticked.remove(stem)
        }
        return copy.canSplit ? copy : self
    }
}

/// Where a split goes and what its files are called (D-94).
public enum StemNaming {
    /// A new folder next to the song: "<song without extension> split", or "… split 2", "… split 3" when taken.
    public static func defaultFolder(for song: URL, exists: (URL) -> Bool) -> URL {
        let parent = song.deletingLastPathComponent()
        let name = safe(song.deletingPathExtension().lastPathComponent) + " split"
        var candidate = parent.appendingPathComponent(name, isDirectory: true)
        var number = 2
        while exists(candidate) {
            candidate = parent.appendingPathComponent("\(name) \(number)", isDirectory: true)
            number += 1
        }
        return candidate
    }

    /// "<song> - Vocals.wav".
    public static func fileName(for song: URL, stem: StemKind) -> String {
        safe("\(song.deletingPathExtension().lastPathComponent) - \(stem.rawValue)") + ".wav"
    }

    /// A name the Mac takes: "/" and ":" become "_", a leading dot (hidden) goes, never empty.
    public static func safe(_ name: String) -> String {
        var safe = String(name.map { $0 == "/" || $0 == ":" || $0.isNewline ? "_" : $0 })
        while safe.hasPrefix(".") {
            safe.removeFirst()
        }
        safe = safe.trimmingCharacters(in: .whitespaces)
        return safe.isEmpty ? "_" : safe
    }
}
