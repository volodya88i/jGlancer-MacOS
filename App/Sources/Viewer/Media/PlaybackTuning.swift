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
    /// A pitch or tempo asked for the current song (D-106): a rate without Keep Pitch, never saved. The next file, a
    /// speed choice or Keep Pitch brings back the saved speed and Keep Pitch.
    private(set) var targetKind: MediaKind?

    var isTargeted: Bool {
        targetKind != nil
    }

    init(playback: PlaybackController, store: PlaybackPreferencesStore) {
        self.playback = playback
        self.store = store
        preferences = store.load()
    }

    /// The remembered speed and "play next" of `kind`, the volume and Keep Pitch, before a file of that kind loads.
    func prepare(for kind: MediaKind) {
        targetKind = nil
        playback.setRate(preferences.rate(for: kind))
        playback.autoAdvance = preferences.playsNext(for: kind)
        playback.volume = preferences.volume
        playback.preservesPitch = preferences.preservesPitch
    }

    func setRate(_ rate: Float, for kind: MediaKind) {
        if isTargeted {
            targetKind = nil
            playback.preservesPitch = preferences.preservesPitch
        }
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
        clearTarget()
        playback.preservesPitch = preserves
        preferences.preservesPitch = preserves
        store.save(preferences)
    }

    // MARK: Target pitch and tempo

    /// How many semitones the current song sounds from its own pitch.
    var heardSemitones: Double {
        playback.preservesPitch ? 0 : PlaybackTarget.semitones(rate: Double(playback.rate))
    }

    /// Plays the current song at `rate` without Keep Pitch, to reach a pitch or a tempo (D-106).
    func setTargetRate(_ rate: Double, for kind: MediaKind) {
        targetKind = kind
        playback.preservesPitch = false
        playback.setExactRate(Float(rate))
    }

    /// Back to the saved speed and Keep Pitch.
    func clearTarget() {
        guard let kind = targetKind else { return }
        targetKind = nil
        playback.setRate(preferences.rate(for: kind))
        playback.preservesPitch = preferences.preservesPitch
    }
}
