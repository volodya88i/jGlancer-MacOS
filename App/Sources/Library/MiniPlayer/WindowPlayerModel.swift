import CoreGraphics
import Foundation
import JGDesign
import JGModel
import JGPlayback
import JGThumbs
import Observation

/// The mini player in the library window (D-88, W-68) — not the preview's `MiniPlayer`: songs play in a bar at the
/// bottom of the window with their own player, so browsing and the previews go on. When another player starts it
/// pauses, and it resumes when that player pauses or closes, unless the user paused it in between.
@MainActor
@Observable
final class WindowPlayerModel {
    let playback = PlaybackController()
    /// Speed and volume of this player only (not saved).
    @ObservationIgnored let tuning: PlaybackTuning
    @ObservationIgnored let liveTime = JGLiveTime()
    private(set) var isOpen = false
    private(set) var cover: CGImage?
    /// The folder of the song playing, shown as a link to it.
    private(set) var folderName: String?
    @ObservationIgnored private var thumbnails: ThumbnailService?
    @ObservationIgnored private var pausedForOther = false
    @ObservationIgnored private var observer: NSObjectProtocol?
    /// One watch of the queue at a time (`followQueue`).
    @ObservationIgnored private var followsQueue = false

    init() {
        tuning = PlaybackTuning(playback: playback, store: PlaybackPreferencesStore(isPersistent: false))
        playback.autoAdvance = true
        playback.onTimeChange = { [liveTime] seconds in liveTime.seconds = seconds }
        playback.onMotionChange = { [liveTime] rate in liveTime.rate = rate }
        observer = NotificationCenter.default.addObserver(
            forName: PlaybackController.playingDidChange, object: nil, queue: .main
        ) { [weak self] note in
            let other = note.object as? PlaybackController
            MainActor.assumeIsolated { self?.otherPlayerChanged(other) }
        }
    }

    var current: PlaybackItem? {
        playback.queue.current
    }

    /// Plays `items` from `index` (at `seconds` into it); the bar opens.
    func play(_ items: [PlaybackItem], from index: Int, at seconds: Double = 0, thumbnails: ThumbnailService, folderName: String?) {
        guard !items.isEmpty else { return }
        self.thumbnails = thumbnails
        self.folderName = folderName
        pausedForOther = false
        isOpen = true
        playback.load(PlaybackQueue(items: items, index: index))
        if seconds > 0 {
            playback.seek(to: seconds)
        }
        loadCover()
        followQueue()
    }

    /// Play / pause by the user: a pause by the user is never undone by another player stopping.
    func togglePlay() {
        pausedForOther = false
        playback.togglePlayPause()
    }

    func next() {
        playback.next()
    }

    func previous() {
        playback.previous()
    }

    func close() {
        playback.stop()
        isOpen = false
        cover = nil
        pausedForOther = false
    }

    /// Another player started (pause for it) or stopped (resume if it made us pause).
    private func otherPlayerChanged(_ other: PlaybackController?) {
        guard let other, other !== playback, isOpen else { return }
        if other.isPlaying, playback.isPlaying {
            pausedForOther = true
            playback.pause()
        } else if !other.isPlaying, pausedForOther {
            pausedForOther = false
            playback.play()
        }
    }

    /// Any change of song — next, previous, the next one playing by itself at the end — brings its cover (D-120).
    private func followQueue() {
        guard !followsQueue else { return }
        followsQueue = true
        withObservationTracking {
            _ = playback.queue.index
            _ = playback.queue.items.count
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                guard let self else { return }
                followsQueue = false
                if isOpen {
                    loadCover()
                }
                followQueue()
            }
        }
    }

    func loadCover() {
        guard let item = current, let thumbnails, let assetID = item.assetID else {
            cover = nil
            return
        }
        let request = ThumbnailRequest(
            assetID: assetID, url: item.url, kind: .audio, typeIdentifier: item.typeIdentifier,
            modifiedAt: item.modifiedAt ?? .distantPast, duration: item.duration, bucket: .small
        )
        Task { [weak self] in
            let image = await thumbnails.thumbnail(for: request, priority: .visible)
            guard let self, current == item else { return }
            cover = image
        }
    }
}
