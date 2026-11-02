import AVFoundation
import JGMatroska

/// Matroska files (MKV, MKA, WebM) through `MatroskaEngine` instead of the player (D-71).
extension PlaybackController {
    nonisolated static func isMatroska(_ url: URL) -> Bool {
        ["mkv", "mka", "webm", "mk3d"].contains(url.pathExtension.lowercased())
    }

    /// The playhead's time, from the player or the Matroska engine; 0 while nothing is loaded.
    public var mediaSeconds: Double {
        if let matroska {
            return matroska.currentTime
        }
        let time = player.currentTime()
        return time.isNumeric ? time.seconds : 0
    }

    func loadMatroska(_ item: PlaybackItem, autoplay: Bool) {
        player.replaceCurrentItem(with: nil)
        status = .loading
        info = nil
        setTime(0, exact: true)
        duration = item.duration
        let url = item.url
        loadTask = Task { [weak self] in
            // Parsing reads the file off the main thread; the engine (with its video layer) is made here.
            let parsed = await Task.detached(priority: .userInitiated) { () -> Result<MatroskaFile, MatroskaError> in
                do {
                    return try .success(MatroskaFile(url: url))
                } catch let error as MatroskaError {
                    return .failure(error)
                } catch {
                    return .failure(.damaged)
                }
            }.value
            guard let self, !Task.isCancelled, queue.current?.url == url else { return }
            let engine = parsed.flatMap { file in
                Result { try MatroskaEngine(file: file) }.mapError { $0 as? MatroskaError ?? .damaged }
            }
            switch engine {
            case let .success(engine): start(engine, autoplay: autoplay)
            case .failure(.unsupported): fail(.unsupported)
            case .failure: fail(.unreadable)
            }
        }
    }

    private func start(_ engine: MatroskaEngine, autoplay: Bool) {
        // The player's observers go before the engine takes over (each removes only its own).
        removeTimeObserver()
        removeStopObserver()
        matroska = engine
        matroskaLayer = engine.videoLayer
        engine.audioRenderer?.volume = volume
        engine.audioRenderer?.isMuted = isMuted || mutesWhileScrubbing
        engine.audioRenderer?.audioTimePitchAlgorithm = pitchAlgorithm
        engine.onEnd = { [weak self] in self?.itemDidEnd() }
        info = MediaInfo(
            isPlayable: true, duration: engine.file.duration, videoSize: engine.videoSize,
            frameRate: engine.videoTrack?.defaultDuration.map { 1 / $0 }, title: engine.file.title
        )
        if let seconds = engine.file.duration {
            duration = seconds
        }
        status = .ready
        engine.start(at: 0, rate: autoplay ? rate : 0)
        isPlaying = autoplay
        if timeObservers > 0 {
            addTimeObserver()
        }
        installStopObserver()
    }

    func closeMatroska() {
        guard let matroska else { return }
        removeStopObserver()
        if timeObserver != nil {
            removeTimeObserver()
            self.matroska = nil
            addTimeObserver()
        }
        matroska.stop()
        self.matroska = nil
        matroskaLayer = nil
        isPlaying = false
    }
}
