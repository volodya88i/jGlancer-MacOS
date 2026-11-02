import AVFoundation

/// The effective mute, the pitch algorithm and the playhead's speed.
public extension PlaybackController {
    /// The playhead's speed: the rate while playing, 0 while paused. Reported through `onMotionChange` so playheads
    /// move smoothly between time updates.
    var motionRate: Double {
        isPlaying ? Double(rate) : 0
    }

    internal var pitchAlgorithm: AVAudioTimePitchAlgorithm {
        preservesPitch ? .spectral : .varispeed
    }

    /// Muted by the user or for a scrub.
    internal func applyMute() {
        player.isMuted = isMuted || mutesWhileScrubbing
        matroska?.audioRenderer?.isMuted = isMuted || mutesWhileScrubbing
    }
}
