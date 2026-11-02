import AVFoundation
import Foundation
import JGMatroska
import Observation

/// Plays the items of a `PlaybackQueue` with one `AVPlayer` (docs/ARCHITECTURE.md §9). Owned by the app model,
/// not by a view, so playback can outlive the viewer later (background mode, Phase 11).
///
/// Time is reported only while someone observes it (`beginTimeUpdates`, for visible scrubbers); otherwise there
/// is no periodic observer and an idle player costs no CPU. Playheads get every update through `onTimeChange`
/// (no SwiftUI work); the observable `currentTime` changes only when the shown second does, for time labels.
@MainActor
@Observable
public final class PlaybackController {
    public enum Status: Equatable, Sendable {
        case idle
        case loading
        case ready
        case failed(PlaybackError)
    }

    /// The player, for an `AVPlayerLayer`.
    @ObservationIgnored public let player = AVPlayer()
    /// The picture of a Matroska file (played by `MatroskaEngine`, not the player), for the viewer's surface.
    public internal(set) var matroskaLayer: AVSampleBufferDisplayLayer?
    @ObservationIgnored var matroska: MatroskaEngine?

    public private(set) var queue = PlaybackQueue()
    public internal(set) var status: Status = .idle
    /// Information about the current item once loaded.
    public internal(set) var info: MediaInfo?
    /// True while playing or waiting to play (not paused).
    public internal(set) var isPlaying = false {
        didSet {
            if isPlaying != oldValue {
                onMotionChange?(motionRate)
                NotificationCenter.default.post(name: Self.playingDidChange, object: self)
            }
        }
    }

    /// Posted (object: the controller) when a controller starts or stops playing: the window's mini player pauses
    /// for other players (D-88).
    public static let playingDidChange = Notification.Name("jGlancer.PlaybackController.playingDidChange")

    /// Seconds, for labels: changes when the rounded second changes while time updates are on, and on every
    /// seek, pause and load.
    public internal(set) var currentTime: Double = 0
    /// Every time update, for playheads (set by the viewer).
    @ObservationIgnored public var onTimeChange: ((Double) -> Void)?
    /// Seconds; from the library until the file's own duration is loaded.
    public internal(set) var duration: Double?
    /// The chosen speed, applied whenever playback runs (`PlaybackSpeed.range`).
    public internal(set) var rate: Float = PlaybackSpeed.normal {
        didSet {
            if rate != oldValue {
                onMotionChange?(motionRate)
            }
        }
    }

    @ObservationIgnored public var onMotionChange: ((Double) -> Void)?

    public var volume: Float = 1 {
        didSet {
            player.volume = volume
            matroska?.audioRenderer?.volume = volume
        }
    }

    public var isMuted = false {
        didSet { applyMute() }
    }

    /// Silent while the user drags the playhead or a segment's start (D-77, W-67); the user's `isMuted` is untouched.
    @ObservationIgnored public var mutesWhileScrubbing = false {
        didSet {
            if mutesWhileScrubbing != oldValue {
                applyMute()
            }
        }
    }

    /// Keeps the pitch at speeds other than 1× (`spectral`); off plays like tape (`varispeed`).
    public var preservesPitch = true {
        didSet {
            player.currentItem?.audioTimePitchAlgorithm = pitchAlgorithm
            matroska?.audioRenderer?.audioTimePitchAlgorithm = pitchAlgorithm
        }
    }

    /// Repeats the current item.
    public var loops = false
    /// Continues with the next item at the end (audio).
    public var autoAdvance = true
    /// Playback pauses here (the end of a selected segment, D-74); nil plays on. Cleared when another item loads.
    @ObservationIgnored public var stopTime: Double? {
        didSet {
            if stopTime != oldValue {
                installStopObserver()
            }
        }
    }

    @ObservationIgnored var stopObserver: StopObserver?

    /// Seconds between time updates while observed. Scrubbers set it with `timeUpdateInterval(duration:width:)`
    /// so the playhead moves about a point per update; a change applies at once.
    @ObservationIgnored public var timeUpdateInterval = maximumUpdateRate {
        didSet {
            if timeUpdateInterval != oldValue, timeObserver != nil {
                removeTimeObserver()
                addTimeObserver()
            }
        }
    }

    /// The fastest time updates (display rate) and the slowest (so a time label never lags noticeably).
    public static let maximumUpdateRate = 1.0 / 30
    public static let minimumUpdateRate = 0.25
    /// Time updates for a playhead that moves on by itself between them (D-77).
    public static let smoothUpdateInterval = 0.1
    @ObservationIgnored var timeObserver: Any?
    @ObservationIgnored var timeObservers = 0
    @ObservationIgnored private var endObserver: NSObjectProtocol?
    @ObservationIgnored private var itemObservation: NSKeyValueObservation?
    @ObservationIgnored private var playerObservation: NSKeyValueObservation?
    @ObservationIgnored var loadTask: Task<Void, Never>?

    public init() {
        player.actionAtItemEnd = .pause
        // Local files need no network-style buffering before starting.
        player.automaticallyWaitsToMinimizeStalling = false
        playerObservation = player.observe(\.timeControlStatus, options: [.new]) { @Sendable [weak self] player, _ in
            let playing = player.timeControlStatus != .paused
            Task { @MainActor in
                // A Matroska file plays outside the player, which stays paused meanwhile.
                guard self?.matroska == nil else { return }
                self?.isPlaying = playing
            }
        }
    }

    // MARK: Queue

    /// Replaces the queue and loads its current item.
    public func load(_ newQueue: PlaybackQueue, autoplay: Bool = true) {
        queue = newQueue
        loadCurrent(autoplay: autoplay)
    }

    /// Replaces the items without interrupting the current one when it is still among them.
    public func replaceItems(_ items: [PlaybackItem]) {
        let current = queue.current
        queue.replaceItems(items, keeping: current?.id)
        if queue.current != current {
            loadCurrent(autoplay: isPlaying)
        }
    }

    /// Drops the current item (its file went to the Trash) and goes on with the next one, or the previous at the end.
    /// Returns false when the queue is now empty.
    @discardableResult
    public func removeCurrent() -> Bool {
        var items = queue.items
        guard items.indices.contains(queue.index) else { return false }
        let index = queue.index
        items.remove(at: index)
        guard !items.isEmpty else {
            stop()
            return false
        }
        load(PlaybackQueue(items: items, index: min(index, items.count - 1)), autoplay: isPlaying)
        return true
    }

    /// Plays the item at `index` of the queue.
    public func select(_ index: Int) {
        guard queue.select(index) else { return }
        loadCurrent(autoplay: true)
    }

    public func next() {
        select(queue.index + 1)
    }

    /// Back to the start of the item, or to the previous one in its first seconds.
    public func previous() {
        switch queue.previousAction(currentTime: mediaSeconds) {
        case .restart: seek(to: 0, precise: true)
        case let .move(index): select(index)
        }
    }

    /// Stops playback and releases the file.
    public func stop() {
        loadTask?.cancel()
        closeMatroska()
        player.pause()
        detachItem()
        player.replaceCurrentItem(with: nil)
        queue = PlaybackQueue()
        status = .idle
        info = nil
        setTime(0, exact: true)
        duration = nil
    }

    // MARK: Loading

    var isFailed: Bool {
        if case .failed = status {
            true
        } else {
            false
        }
    }

    /// Starts the current item at once and loads its information alongside; an unplayable file fails.
    private func loadCurrent(autoplay: Bool) {
        loadTask?.cancel()
        stopTime = nil
        detachItem()
        closeMatroska()
        guard let item = queue.current else {
            stop()
            return
        }
        if Self.isMatroska(item.url) {
            loadMatroska(item, autoplay: autoplay)
            return
        }
        status = .loading
        info = nil
        setTime(0, exact: true)
        duration = item.duration
        let asset = AVURLAsset(url: item.url)
        let playerItem = AVPlayerItem(asset: asset)
        playerItem.audioTimePitchAlgorithm = pitchAlgorithm
        player.replaceCurrentItem(with: playerItem)
        attach(playerItem)
        if autoplay {
            player.defaultRate = rate
            player.play()
        }
        loadTask = Task { [weak self] in
            let info = try? await MediaInfo.load(asset)
            guard let self, !Task.isCancelled, player.currentItem === playerItem else { return }
            guard let info else {
                fail(.unreadable)
                return
            }
            guard info.isPlayable else {
                fail(.unsupported)
                return
            }
            self.info = info
            if let seconds = info.duration {
                duration = seconds
            }
            if status == .loading, playerItem.status == .readyToPlay {
                status = .ready
            }
        }
    }

    func fail(_ error: PlaybackError) {
        player.pause()
        status = .failed(error)
    }

    private func attach(_ item: AVPlayerItem) {
        itemObservation = item.observe(\.status, options: [.new]) { @Sendable [weak self] item, _ in
            let status = item.status
            Task { @MainActor in self?.itemStatusChanged(status, of: item) }
        }
        endObserver = NotificationCenter.default.addObserver(
            forName: AVPlayerItem.didPlayToEndTimeNotification, object: item, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.itemDidEnd() }
        }
    }

    private func detachItem() {
        itemObservation?.invalidate()
        itemObservation = nil
        if let endObserver {
            NotificationCenter.default.removeObserver(endObserver)
        }
        endObserver = nil
    }

    private func itemStatusChanged(_ itemStatus: AVPlayerItem.Status, of item: AVPlayerItem) {
        guard player.currentItem === item else { return }
        switch itemStatus {
        case .readyToPlay:
            if status == .loading, info != nil {
                status = .ready
            }
        case .failed:
            if status == .loading || status == .ready {
                fail(info == nil ? .unsupported : .unreadable)
            }
        default:
            break
        }
    }

    func itemDidEnd() {
        switch queue.endAction(loop: loops, autoAdvance: autoAdvance) {
        case .replay:
            seek(to: 0, precise: true)
            if matroska != nil {
                play()
            } else {
                player.play()
            }
        case let .advance(index):
            select(index)
        case .stop:
            if matroska != nil {
                isPlaying = false
            }
            setTime(duration ?? mediaSeconds, exact: true)
        }
    }
}
