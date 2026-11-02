import AppKit
import JGPlayback
import MediaPlayer

/// The keyboard's media keys (play/pause, next, previous) and the system's Now Playing (D-92): they drive the open
/// video or audio viewer, else the window's mini player. macOS sends the keys to the app that last reported playing,
/// so Now Playing follows every player's start and stop.
@MainActor
final class MediaKeys {
    private weak var appModel: AppModel?
    private var observer: NSObjectProtocol?

    init(appModel: AppModel) {
        self.appModel = appModel
    }

    func start() {
        let center = MPRemoteCommandCenter.shared()
        handle(center.togglePlayPauseCommand) { $0.togglePlay() }
        handle(center.playCommand) { $0.play() }
        handle(center.pauseCommand) { $0.pause() }
        handle(center.nextTrackCommand) { $0.next() }
        handle(center.previousTrackCommand) { $0.previous() }
        observer = NotificationCenter.default.addObserver(
            forName: PlaybackController.playingDidChange, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateNowPlaying() }
        }
    }

    private func handle(_ command: MPRemoteCommand, _ action: @escaping @MainActor (Target) -> Void) {
        command.isEnabled = true
        command.addTarget { [weak self] _ in
            MainActor.assumeIsolated {
                guard let target = self?.target else { return .noActionableNowPlayingItem }
                action(target)
                self?.updateNowPlaying()
                return .success
            }
        }
    }

    /// The player the keys drive.
    @MainActor
    private enum Target {
        case viewer(MediaViewerModel)
        case miniPlayer(WindowPlayerModel)

        func togglePlay() {
            switch self {
            case let .viewer(model): model.perform(.togglePlay)
            case let .miniPlayer(player): player.togglePlay()
            }
        }

        func play() {
            if !playback.isPlaying {
                togglePlay()
            }
        }

        func pause() {
            if playback.isPlaying {
                togglePlay()
            }
        }

        func next() {
            switch self {
            case let .viewer(model): model.perform(.next)
            case let .miniPlayer(player): player.next()
            }
        }

        func previous() {
            switch self {
            case let .viewer(model): model.perform(.previous)
            case let .miniPlayer(player): player.previous()
            }
        }

        var playback: PlaybackController {
            switch self {
            case let .viewer(model): model.playback
            case let .miniPlayer(player): player.playback
            }
        }
    }

    private var target: Target? {
        guard let appModel else { return nil }
        if let viewer = appModel.mediaViewer {
            return .viewer(viewer)
        }
        return appModel.windowPlayer.isOpen ? .miniPlayer(appModel.windowPlayer) : nil
    }

    private func updateNowPlaying() {
        let info = MPNowPlayingInfoCenter.default()
        guard let target, let item = target.playback.queue.current else {
            info.nowPlayingInfo = nil
            info.playbackState = .stopped
            return
        }
        info.nowPlayingInfo = [
            MPMediaItemPropertyTitle: item.name,
            MPMediaItemPropertyPlaybackDuration: target.playback.duration ?? 0,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: target.playback.mediaSeconds,
            MPNowPlayingInfoPropertyPlaybackRate: target.playback.isPlaying ? 1.0 : 0.0,
        ]
        info.playbackState = target.playback.isPlaying ? .playing : .paused
    }
}
