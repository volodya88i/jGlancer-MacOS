import JGModel
import JGPlayback
import Observation

/// Applies and remembers the player's speed and "play next" per kind, volume and Keep Pitch (docs/FEATURES.md §5), for the
/// viewer and the previews alike. Owned by the app model.
@MainActor
@Observable
final class PlaybackTuning {
    let playback: PlaybackController
    @ObservationIgnored private let store: PlaybackPreferencesStore
    private(set) var preferences: PlaybackPreferences

    init(playback: PlaybackController, store: PlaybackPreferencesStore) {
        self.playback = playback
        self.store = store
        preferences = store.load()
    }

    /// The remembered speed and "play next" of `kind`, the volume and Keep Pitch, before a file of that kind loads.
    func prepare(for kind: MediaKind) {
        playback.setRate(preferences.rate(for: kind))
        playback.autoAdvance = preferences.playsNext(for: kind)
        playback.volume = preferences.volume
        playback.preservesPitch = preferences.preservesPitch
    }

    func setRate(_ rate: Float, for kind: MediaKind) {
        playback.setRate(rate)
        preferences.setRate(playback.rate, for: kind)
        store.save(preferences)
    }

    func setPlaysNext(_ playsNext: Bool, for kind: MediaKind) {
        playback.autoAdvance = playsNext
        preferences.setPlaysNext(playsNext, for: kind)
        store.save(preferences)
    }

    func setSegmentFades(_ fades: Bool) {
        preferences.segmentFades = fades
        store.save(preferences)
    }

    func setVolume(_ volume: Float) {
        playback.volume = min(max(volume, 0), 1)
        playback.isMuted = false
        preferences.volume = playback.volume
        store.save(preferences)
    }

    func setPreservesPitch(_ preserves: Bool) {
        playback.preservesPitch = preserves
        preferences.preservesPitch = preserves
        store.save(preferences)
    }
}
