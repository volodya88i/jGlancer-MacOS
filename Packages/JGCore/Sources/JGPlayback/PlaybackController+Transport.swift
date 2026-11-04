import AVFoundation
import JGMatroska

/// Play, pause, seeking and speed: the player, or the Matroska engine for MKV files.
public extension PlaybackController {
    func play() {
        if let matroska {
            guard !isFailed else { return }
            let start = duration.map { mediaSeconds >= $0 - 0.05 } == true ? 0 : mediaSeconds
            matroska.start(at: start, rate: rate)
            isPlaying = true
            return
        }
        guard player.currentItem != nil, !isFailed else { return }
        if let duration, player.currentTime().seconds >= duration - 0.05 {
            seek(to: 0, precise: true)
        }
        player.defaultRate = rate
        player.play()
    }

    func pause() {
        if let matroska {
            matroska.setRate(0)
            isPlaying = false
        } else {
            player.pause()
        }
        setTime(mediaSeconds, exact: true)
    }

    func togglePlayPause() {
        if isPlaying {
            pause()
        } else {
            play()
        }
    }

    /// Jumps to `seconds`; `precise` is exact to the frame (slower), else the nearest keyframe area (scrubbing).
    func seek(to seconds: Double, precise: Bool = true) {
        let target = min(max(seconds, 0), duration ?? .greatestFiniteMagnitude)
        if let matroska {
            matroska.start(at: target, rate: isPlaying ? rate : 0)
            setTime(target, exact: true)
            return
        }
        let tolerance = precise ? CMTime.zero : CMTime(seconds: 0.1, preferredTimescale: 600)
        player.seek(to: CMTime(seconds: target, preferredTimescale: 600), toleranceBefore: tolerance, toleranceAfter: tolerance)
        setTime(target, exact: true)
    }

    /// Moves by `seconds` (negative goes back).
    func skip(by seconds: Double) {
        seek(to: mediaSeconds + seconds, precise: true)
    }

    /// Pauses and moves by whole video frames (negative goes back).
    func step(frames: Int) {
        if let matroska {
            let frame = matroska.videoTrack?.defaultDuration ?? 1.0 / 30
            pause()
            seek(to: mediaSeconds + Double(frames) * frame, precise: true)
            return
        }
        guard let item = player.currentItem, info?.hasVideo == true else { return }
        player.pause()
        item.step(byCount: frames)
    }

    /// Sets the speed (clamped to `PlaybackSpeed.range`); takes effect at once while playing.
    func setRate(_ newRate: Float) {
        setExactRate(PlaybackSpeed.clamped(newRate))
    }

    /// Sets the speed to exactly `newRate` within `PlaybackSpeed.range`, not rounded to the fine step: a target pitch
    /// or tempo (D-106).
    func setExactRate(_ newRate: Float) {
        rate = min(max(newRate, PlaybackSpeed.range.lowerBound), PlaybackSpeed.range.upperBound)
        if let matroska, isPlaying {
            matroska.setRate(rate)
        }
        player.defaultRate = rate
        if player.rate != 0 {
            player.rate = rate
        }
    }

    /// Reports a time to the playhead, and to `currentTime` when `exact` or when the shown second changes.
    internal func setTime(_ seconds: Double, exact: Bool) {
        guard seconds.isFinite else { return }
        onTimeChange?(seconds)
        if exact || seconds.rounded() != currentTime.rounded() {
            currentTime = seconds
        }
    }
}
