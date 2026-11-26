import Foundation

/// A part of a song that the splitter writes as its own file (D-94, D-97; Windows W-85).
public enum StemKind: String, CaseIterable, Codable, Sendable {
    case vocals = "Vocals"
    case drums = "Drums"
    case bass = "Bass"
    case guitar = "Guitar"
    case piano = "Piano"
    case other = "Other"
    /// Everything but the vocals (2 stems): the song less the vocals, so the two add up to the song.
    case instrumental = "Instrumental"
}

/// The network a split runs: Demucs with 4 sources or 6, or Mel-Band RoFormer with the vocals alone (2 stems at high
/// quality, D-131).
public enum StemNetwork: String, CaseIterable, Sendable {
    case four
    case six
    case vocals
}

/// What the split window offers: 2 stems (vocals and the instrumental, from the 4-stem network), 4 (vocals, drums,
/// bass, the rest) or 6 (also guitar and piano).
public enum StemMode: String, CaseIterable, Codable, Sendable {
    case two
    case four
    case six

    /// The Demucs network the mode runs: for 2 stems the 4-stem one, which separates vocals better than the 6-stem
    /// one (`StemChoice.network` may take RoFormer instead).
    public var network: StemNetwork {
        self == .six ? .six : .four
    }
}

/// One model as the app uses it: its name, the order of the sources it produces (the network's own order), its sample
/// rate and the length of the piece of audio it takes at once (D-97, D-131). `isFull`: the weights at full precision;
/// otherwise compact: half-precision weights computing at full precision, half the size on disk, inaudibly different
/// (D-103, W-92).
public struct StemModelInfo: Hashable, Sendable {
    public let network: StemNetwork
    /// The compiled Core ML model folder in the app's models folder.
    public let name: String
    public let sources: [StemKind]
    public let sampleRate: Int
    public let segmentFrames: Int
    public let isFull: Bool

    private static let fourSources: [StemKind] = [.drums, .bass, .other, .vocals]
    private static let sixSources: [StemKind] = [.drums, .bass, .other, .vocals, .guitar, .piano]

    private static func make(_ network: StemNetwork, _ name: String, full: Bool) -> StemModelInfo {
        switch network {
        case .four, .six:
            StemModelInfo(
                network: network, name: name, sources: network == .six ? sixSources : fourSources, sampleRate: 44100,
                segmentFrames: 343_980, isFull: full
            )
        case .vocals:
            StemModelInfo(network: network, name: name, sources: [.vocals], sampleRate: 44100, segmentFrames: 352_800, isFull: full)
        }
    }

    /// Demucs v4 Hybrid Transformer, 4 sources (htdemucs).
    public static let four = make(.four, "htdemucs", full: true)
    /// Demucs v4 Hybrid Transformer, 6 sources (htdemucs_6s).
    public static let six = make(.six, "htdemucs_6s", full: true)
    public static let fourCompact = make(.four, "htdemucs-compact", full: false)
    public static let sixCompact = make(.six, "htdemucs_6s-compact", full: false)
    /// Mel-Band RoFormer, the vocals (Kimberley Jensen's model, D-131).
    public static let roformer = make(.vocals, "mel_band_roformer", full: true)
    public static let roformerCompact = make(.vocals, "mel_band_roformer-compact", full: false)

    public static let all = [four, six, fourCompact, sixCompact, roformer, roformerCompact]

    public static func model(for network: StemNetwork, full: Bool = true) -> StemModelInfo {
        switch (network, full) {
        case (.four, true): four
        case (.six, true): six
        case (.four, false): fourCompact
        case (.six, false): sixCompact
        case (.vocals, true): roformer
        case (.vocals, false): roformerCompact
        }
    }

    /// The stems of a mode in the order the window lists them.
    public static func shown(_ mode: StemMode) -> [StemKind] {
        switch mode {
        case .two: [.vocals, .instrumental]
        case .four: [.vocals, .drums, .bass, .other]
        case .six: [.vocals, .drums, .bass, .guitar, .piano, .other]
        }
    }

    /// How this network makes `stem`: one of its sources, or for the instrumental the song less the vocals; nil when
    /// it has neither.
    public func part(of stem: StemKind) -> StemOutput.Part? {
        guard stem != .instrumental else { return sources.firstIndex(of: .vocals).map(StemOutput.Part.songWithout) }
        return sources.firstIndex(of: stem).map(StemOutput.Part.source)
    }
}

/// The split window's choice: the mode, the stems ticked and, for 2 stems, the quality (remembered between uses, not
/// the folder). At least one stem of the mode stays ticked.
public struct StemChoice: Hashable, Codable, Sendable {
    public private(set) var mode: StemMode
    public private(set) var ticked: Set<StemKind>
    /// 2 stems with Mel-Band RoFormer instead of the 4-stem Demucs: cleaner, a larger download, slower (D-131).
    public private(set) var highQuality: Bool

    public init(mode: StemMode = .four, ticked: Set<StemKind>? = nil, highQuality: Bool = false) {
        self.mode = mode
        self.ticked = ticked ?? Set(StemModelInfo.shown(mode))
        self.highQuality = highQuality
    }

    private enum CodingKeys: String, CodingKey {
        case mode, ticked, highQuality
    }

    /// A choice saved before High Quality existed reads as Standard.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mode = try container.decode(StemMode.self, forKey: .mode)
        ticked = try container.decode(Set<StemKind>.self, forKey: .ticked)
        highQuality = try container.decodeIfPresent(Bool.self, forKey: .highQuality) ?? false
    }

    /// The network a split with this choice runs.
    public var network: StemNetwork {
        mode == .two && highQuality ? .vocals : mode.network
    }

    /// Standard or High Quality (it counts for 2 stems only).
    public func with(highQuality isHigh: Bool) -> StemChoice {
        var copy = self
        copy.highQuality = isHigh
        return copy
    }

    /// The ticked stems of the mode, in the window's order.
    public var stems: [StemKind] {
        StemModelInfo.shown(mode).filter(ticked.contains)
    }

    public var canSplit: Bool {
        !stems.isEmpty
    }

    /// Another mode: the stems both modes have keep their ticks; the new mode's own stems (guitar, piano, the instrumental) come
    /// ticked, and so does everything when nothing would be left ticked.
    public func with(mode newMode: StemMode) -> StemChoice {
        guard newMode != mode else { return self }
        let old = Set(StemModelInfo.shown(mode))
        let kept = StemModelInfo.shown(newMode).filter { !old.contains($0) || ticked.contains($0) }
        return StemChoice(
            mode: newMode, ticked: kept.isEmpty ? Set(StemModelInfo.shown(newMode)) : Set(kept), highQuality: highQuality
        )
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
