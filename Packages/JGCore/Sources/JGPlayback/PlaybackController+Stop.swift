import AVFoundation
import JGMatroska

/// A boundary observer on whatever plays (the player or the Matroska engine) that pauses at `stopTime`.
struct StopObserver {
    let token: Any
    /// The engine that owns `token`; nil for the player (each removes only its own observers).
    let engine: MatroskaEngine?
}

extension PlaybackController {
    func installStopObserver() {
        removeStopObserver()
        guard let stopTime else { return }
        let reached: @Sendable () -> Void = { [weak self] in
            MainActor.assumeIsolated { self?.reachedStopTime() }
        }
        if let matroska {
            stopObserver = StopObserver(token: matroska.addBoundaryTimeObserver(at: stopTime, reached), engine: matroska)
        } else {
            let time = NSValue(time: CMTime(seconds: stopTime, preferredTimescale: 600))
            stopObserver = StopObserver(token: player.addBoundaryTimeObserver(forTimes: [time], queue: .main, using: reached), engine: nil)
        }
    }

    func removeStopObserver() {
        guard let stopObserver else { return }
        if let engine = stopObserver.engine {
            engine.removeTimeObserver(stopObserver.token)
        } else {
            player.removeTimeObserver(stopObserver.token)
        }
        self.stopObserver = nil
    }

    /// The boundary fires a moment late: pause, then show exactly the stop time.
    private func reachedStopTime() {
        guard let stopTime, isPlaying else { return }
        pause()
        seek(to: stopTime, precise: true)
    }
}
