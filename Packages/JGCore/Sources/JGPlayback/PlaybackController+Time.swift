import AVFoundation

/// Time updates: a periodic observer only while a scrubber is visible, at the rate its playhead needs.
public extension PlaybackController {
    /// Starts keeping `currentTime` current; balance with `endTimeUpdates`.
    func beginTimeUpdates() {
        timeObservers += 1
        setTime(mediaSeconds, exact: true)
        if timeObserver == nil {
            addTimeObserver()
        }
    }

    func endTimeUpdates() {
        timeObservers = max(0, timeObservers - 1)
        if timeObservers == 0 {
            removeTimeObserver()
        }
    }

    /// The update interval at which a playhead `width` points wide for `duration` seconds moves about one point
    /// per update at the current speed, within `maximumUpdateRate` … `minimumUpdateRate`.
    func timeUpdateInterval(duration: Double?, width: Double) -> Double {
        guard let duration, duration > 0, width > 0 else { return Self.maximumUpdateRate }
        let secondsPerPoint = duration / width / Double(max(rate, PlaybackSpeed.range.lowerBound))
        return min(max(secondsPerPoint, Self.maximumUpdateRate), Self.minimumUpdateRate)
    }

    internal func addTimeObserver() {
        if let matroska {
            timeObserver = matroska.addPeriodicTimeObserver(interval: timeUpdateInterval) { [weak self] seconds in
                MainActor.assumeIsolated { self?.setTime(seconds, exact: false) }
            }
            return
        }
        let interval = CMTime(seconds: timeUpdateInterval, preferredTimescale: 600)
        timeObserver = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            MainActor.assumeIsolated {
                if time.isNumeric {
                    self?.setTime(time.seconds, exact: false)
                }
            }
        }
    }

    internal func removeTimeObserver() {
        if let timeObserver {
            if let matroska {
                matroska.removeTimeObserver(timeObserver)
            } else {
                player.removeTimeObserver(timeObserver)
            }
        }
        timeObserver = nil
    }
}
