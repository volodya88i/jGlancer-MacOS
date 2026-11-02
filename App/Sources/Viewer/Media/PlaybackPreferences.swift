import Foundation
import JGModel
import JGPlayback

/// Speed and "play next" per kind, volume and pitch preservation, remembered across launches (docs/FEATURES.md §5).
struct PlaybackPreferences: Codable, Equatable {
    var videoRate = PlaybackSpeed.normal
    var audioRate = PlaybackSpeed.normal
    var volume: Float = 1
    var preservesPitch = true
    /// Continue with the next file at the end: music does, a video stops (D-48, D-72).
    var videoPlaysNext = false
    var audioPlaysNext = true
    /// Short fades at both ends of an exported audio segment (D-73).
    var segmentFades = true

    init() {}

    /// Keys missing from older saves keep their defaults.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = PlaybackPreferences()
        videoRate = try container.decodeIfPresent(Float.self, forKey: .videoRate) ?? defaults.videoRate
        audioRate = try container.decodeIfPresent(Float.self, forKey: .audioRate) ?? defaults.audioRate
        volume = try container.decodeIfPresent(Float.self, forKey: .volume) ?? defaults.volume
        preservesPitch = try container.decodeIfPresent(Bool.self, forKey: .preservesPitch) ?? defaults.preservesPitch
        videoPlaysNext = try container.decodeIfPresent(Bool.self, forKey: .videoPlaysNext) ?? defaults.videoPlaysNext
        audioPlaysNext = try container.decodeIfPresent(Bool.self, forKey: .audioPlaysNext) ?? defaults.audioPlaysNext
        segmentFades = try container.decodeIfPresent(Bool.self, forKey: .segmentFades) ?? defaults.segmentFades
    }

    func playsNext(for kind: MediaKind) -> Bool {
        kind == .video ? videoPlaysNext : audioPlaysNext
    }

    mutating func setPlaysNext(_ playsNext: Bool, for kind: MediaKind) {
        if kind == .video {
            videoPlaysNext = playsNext
        } else {
            audioPlaysNext = playsNext
        }
    }

    func rate(for kind: MediaKind) -> Float {
        kind == .video ? videoRate : audioRate
    }

    mutating func setRate(_ rate: Float, for kind: MediaKind) {
        if kind == .video {
            videoRate = rate
        } else {
            audioRate = rate
        }
    }
}

/// Saves and restores `PlaybackPreferences` in user defaults.
struct PlaybackPreferencesStore {
    private static let key = "PlaybackPreferences"
    /// False for benchmark runs, so they do not overwrite the user's preferences.
    let isPersistent: Bool

    func load() -> PlaybackPreferences {
        guard isPersistent, let data = UserDefaults.standard.data(forKey: Self.key),
              let preferences = try? JSONDecoder().decode(PlaybackPreferences.self, from: data)
        else { return PlaybackPreferences() }
        return preferences
    }

    func save(_ preferences: PlaybackPreferences) {
        guard isPersistent, let data = try? JSONEncoder().encode(preferences) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
