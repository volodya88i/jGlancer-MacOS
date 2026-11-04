import CoreGraphics
import Foundation
import JGDesign
import JGModel
import JGPlayback
import JGThumbs
import Observation

/// A key or menu command of the video and audio viewer (docs/FEATURES.md §4.2–4.3, §15).
enum MediaCommand: Equatable {
    case togglePlay
    /// Seconds forward (negative: back).
    case seek(Double)
    case previous
    case next
    /// Video frames forward (negative: back).
    case step(Int)
    /// Fine speed steps up (negative: down).
    case speed(Int)
    case resetSpeed
    /// Volume steps up (negative: down).
    case volume(Int)
    case toggleFullScreen
    /// S: segment selection on or off (D-77).
    case toggleSegment
    /// M: mute (the full player only, D-77).
    case toggleMute
    /// P: the frame on screen as a PNG next to the video; ⇧P: to the pasteboard (D-80).
    case saveFrame
    case copyFrame
}

/// The video or audio viewer's state: the shared `PlaybackController` playing the files of one kind from one
/// folder (DECISIONS D-09), remembered speed and volume, cover art and waveform of the current audio file, and
/// filmstrip thumbnails.
@MainActor
@Observable
final class MediaViewerModel {
    /// Cover art of the current audio file.
    enum Cover: Equatable {
        case loading
        case none
        case image(CGImage)
    }

    let kind: MediaKind
    let playback: PlaybackController
    /// Folder of a file opened from outside the library, offered for adding.
    private(set) var folderToOffer: URL?
    /// Top bar, controls and filmstrip (they hide while video plays).
    var isChromeVisible = true
    private(set) var cover: Cover = .loading
    private(set) var waveform: JGWaveformPeaks?
    /// Segment selection (D-73): the chosen part of the current file while the mode is on; nil when it is off.
    var segment: ClosedRange<Double>?
    /// Finer peaks of the zoomed-in part of the waveform, while selecting.
    var waveformDetail: JGWaveformDetail?
    @ObservationIgnored var detailTask: Task<Void, Never>?
    /// Settings: exported WAV, AIFF and FLAC segments keep their format (D-74).
    @ObservationIgnored var segmentKeepsAudioFormat = true
    /// Settings: video segments are cut exactly, encoded again (D-108).
    @ObservationIgnored var segmentCutsExactly = true
    /// Tempo and key of the current song (D-106), once known; `isAnalyzing` while they are looked for, and
    /// `foundNothing` when the song was analyzed without a result. Set by `MediaViewerModel+Analysis`.
    var analysis: AudioAnalysis?
    var isAnalyzing = false
    var foundNothing = false
    @ObservationIgnored var analyses: AudioAnalyses?
    @ObservationIgnored var analysisTask: Task<Void, Never>?
    /// A one-line confirmation (a toast), set by the app.
    @ObservationIgnored var showMessage: ((String) -> Void)?

    /// The playhead's time, fed by the player outside SwiftUI.
    @ObservationIgnored let liveTime = JGLiveTime()
    /// The library's thumbnails, or a memory-only service for files outside the library.
    @ObservationIgnored let thumbnails: ThumbnailService
    @ObservationIgnored let waveforms: WaveformService
    @ObservationIgnored let tuning: PlaybackTuning
    /// Stand-in ids for files outside the library (keys of the private thumbnail service).
    @ObservationIgnored private var outsideIDs: [URL: Int64] = [:]

    /// Seconds moved by ← and →.
    static let seekStep = 5.0
    /// Volume change of ↑ and ↓.
    static let volumeStep: Float = 0.1

    init(
        kind: MediaKind, queue: PlaybackQueue, playback: PlaybackController, thumbnails: ThumbnailService?,
        waveforms: WaveformService, tuning: PlaybackTuning, folderToOffer: URL? = nil,
        segmentKeepsAudioFormat: Bool = true
    ) {
        self.kind = kind
        self.playback = playback
        self.thumbnails = thumbnails ?? ThumbnailService(disk: nil, memoryLimitBytes: 8 * 1024 * 1024)
        self.waveforms = waveforms
        self.tuning = tuning
        self.folderToOffer = folderToOffer
        self.segmentKeepsAudioFormat = segmentKeepsAudioFormat
        tuning.prepare(for: kind)
        playback.loops = false
        playback.onTimeChange = { [liveTime] seconds in liveTime.seconds = seconds }
        playback.onMotionChange = { [liveTime] rate in liveTime.rate = rate }
        playback.load(queue)
    }

    var current: PlaybackItem? {
        playback.queue.current
    }

    var isFailed: Bool {
        if case .failed = playback.status {
            true
        } else {
            false
        }
    }

    /// Stops playback and releases the file (leaving the viewer; background playback comes in Phase 11).
    func close() {
        endSegmentMode()
        playback.stop()
        playback.onTimeChange = nil
        playback.onMotionChange = nil
    }

    func dismissFolderOffer() {
        folderToOffer = nil
    }

    /// The folder listing of an outside file arrived.
    func replaceItems(_ items: [PlaybackItem]) {
        playback.replaceItems(items)
    }

    // MARK: Commands

    /// Runs a command; `toggleFullScreen` belongs to the window and is handled by the view.
    func perform(_ command: MediaCommand) {
        switch command {
        case .togglePlay: togglePlayInSegment()
        case let .seek(seconds): playback.skip(by: seconds)
        case .previous: playback.previous()
        case .next: playback.next()
        case let .step(frames): playback.step(frames: frames)
        case .speed, .resetSpeed, .volume, .toggleMute: adjust(command)
        case .toggleFullScreen: break
        case .toggleSegment: toggleSegmentMode()
        case .saveFrame: saveFrame(copying: false)
        case .copyFrame: saveFrame(copying: true)
        }
    }

    /// Speed, volume and mute.
    private func adjust(_ command: MediaCommand) {
        switch command {
        case let .speed(steps): setRate(PlaybackSpeed.stepped(playback.rate, by: steps))
        case .resetSpeed: setRate(PlaybackSpeed.normal)
        case let .volume(steps): setVolume(playback.volume + Float(steps) * Self.volumeStep)
        case .toggleMute: playback.isMuted.toggle()
        default: break
        }
    }

    func setRate(_ rate: Float) {
        tuning.setRate(rate, for: kind)
    }

    func setVolume(_ volume: Float) {
        tuning.setVolume(volume)
    }

    func setPreservesPitch(_ preserves: Bool) {
        tuning.setPreservesPitch(preserves)
    }

    func toggleLoop() {
        playback.loops.toggle()
    }

    /// "Play next": continue with the next file at the end, remembered per kind.
    func togglePlaysNext() {
        tuning.setPlaysNext(!playback.autoAdvance, for: kind)
    }

    // MARK: Cover, waveform, thumbnails

    /// Cover art of the current audio file (run from the view's task, cancelled when the item changes).
    func loadCover(for item: PlaybackItem) async {
        cover = .loading
        guard item.kind == .audio else { return }
        let image = await thumbnails.thumbnail(for: thumbnailRequest(for: item, bucket: .large), priority: .visible)
        guard !Task.isCancelled, current == item else { return }
        cover = image.map(Cover.image) ?? .none
    }

    /// The waveform of the current audio file, progressively; of a video's sound when `video` (D-110).
    func loadWaveform(for item: PlaybackItem, video: Bool = false) async {
        waveform = nil
        guard item.kind == .audio || (video && item.kind == .video) else { return }
        let request = WaveformRequest(url: item.url, assetID: item.assetID, modifiedAt: item.modifiedAt)
        for await partial in waveforms.waveform(for: request) {
            guard !Task.isCancelled, current == item else { return }
            waveform = JGWaveformPeaks(
                lows: (0 ..< partial.count).map(partial.low(at:)), highs: (0 ..< partial.count).map(partial.high(at:))
            )
        }
    }

    /// The cover art of the queue item at `index` (a swipe's neighbor), from the thumbnail cache when it is there.
    func cover(at index: Int) async -> CGImage? {
        let items = playback.queue.items
        guard items.indices.contains(index) else { return nil }
        let request = thumbnailRequest(for: items[index], bucket: .large)
        if let cached = thumbnails.cachedThumbnail(for: request) {
            return cached
        }
        return await thumbnails.thumbnail(for: request, priority: .visible)
    }

    /// A thumbnail request for a queue item (filmstrip, cover art).
    func thumbnailRequest(for item: PlaybackItem, bucket: ThumbnailBucket) -> ThumbnailRequest {
        ThumbnailRequest(
            assetID: item.assetID ?? outsideID(for: item.url), url: item.url, kind: item.kind,
            typeIdentifier: item.typeIdentifier, modifiedAt: item.modifiedAt ?? .distantPast,
            duration: item.duration, bucket: bucket
        )
    }

    private func outsideID(for url: URL) -> Int64 {
        if let id = outsideIDs[url] {
            return id
        }
        let id = Int64(outsideIDs.count + 1)
        outsideIDs[url] = id
        return id
    }
}

extension MediaViewerModel: FilmstripSource {
    var filmstripCount: Int {
        playback.queue.count
    }

    var filmstripIndex: Int {
        playback.queue.index
    }

    var filmstripThumbnails: ThumbnailService {
        thumbnails
    }

    func filmstripItem(at index: Int) -> FilmstripItem? {
        let items = playback.queue.items
        guard items.indices.contains(index) else { return nil }
        let item = items[index]
        return FilmstripItem(name: item.name, kind: item.kind, thumbnail: thumbnailRequest(for: item, bucket: .small))
    }

    func filmstripSelect(_ index: Int) {
        playback.select(index)
    }
}

extension PlaybackItem {
    /// A library asset as a queue item.
    init(asset: Asset) {
        self.init(
            url: asset.url, name: asset.name, kind: asset.kind, assetID: asset.id, modifiedAt: asset.modifiedAt,
            typeIdentifier: asset.typeIdentifier, duration: asset.duration
        )
    }
}
