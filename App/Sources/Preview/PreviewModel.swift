import CoreGraphics
import Foundation
import JGDesign
import JGModel
import JGPlayback
import JGScanner
import JGStore
import JGThumbs
import Observation

/// What the preview pane and Quick Preview show for the library's selection (docs/FEATURES.md §2–3): the focused
/// file (a photo decoded for the preview, or video / audio loaded into the app's player) and the selection count.
///
/// The pane never starts playback on selection; Quick Preview autoplays (`autoplayInPreview`, default on).
/// Selecting another file replaces the previous one. While a viewer is open the previews stand aside.
@MainActor
@Observable
final class PreviewModel {
    /// The focused file, once its row is loaded.
    private(set) var asset: Asset?
    /// Selected files (the pane summarizes several).
    private(set) var selectionCount = 0
    /// Photo: the best image so far (cached thumbnail, then a decode at preview size).
    var picture: CGImage?
    /// Audio: cover art, if the file has one.
    private(set) var cover: CGImage?
    private(set) var waveform: JGWaveformPeaks?
    /// True while Quick Preview is on screen.
    private(set) var isQuickPreviewOpen = false
    /// Files from Finder (Services ▸ Quick Preview) shown instead of the library's focus, and the one shown.
    private(set) var externalFiles: [URL] = []
    private(set) var externalIndex = 0
    /// A folded image sequence previewed: its frame timeline (W-86); nil for anything else.
    var sequence: SequencePlayback?

    /// The frames of the folded sequence headed by an asset, if it heads one (set by the app; W-86).
    @ObservationIgnored var foldedSequence: ((Int64) -> [Int64]?)?
    @ObservationIgnored var sequenceAssets: [Asset] = []
    /// The first frame's own decode, shown while the first frame is.
    @ObservationIgnored var headPicture: CGImage?
    @ObservationIgnored var frameLoad: Task<Void, Never>?
    @ObservationIgnored var sequenceClock: Task<Void, Never>?

    @ObservationIgnored let playback: PlaybackController
    @ObservationIgnored let tuning: PlaybackTuning
    /// The playheads' time, fed by the player outside SwiftUI.
    @ObservationIgnored let liveTime = JGLiveTime()
    @ObservationIgnored private let store: LibraryStore
    var libraryStore: LibraryStore {
        store
    }

    @ObservationIgnored private let thumbnails: ThumbnailService
    /// Memory only, for files outside the library (nothing of theirs goes into the library's cache).
    @ObservationIgnored private let outsideThumbnails = ThumbnailService(disk: nil, memoryLimitBytes: 16 * 1024 * 1024)
    @ObservationIgnored private let classifier = MediaClassifier()
    @ObservationIgnored private let waveforms: () -> WaveformService
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    /// The player holds our file (not a viewer's).
    @ObservationIgnored private var ownsPlayback = false
    @ObservationIgnored private var isSuspended = false
    @ObservationIgnored private var focusID: Int64?

    /// Longest side, in pixels, of photo decodes for the previews (Quick Preview can be large).
    nonisolated static let photoPixels = 1600

    /// Quick Preview starts video and audio by itself (Settings → Playback).
    @ObservationIgnored var autoplayInPreview = true

    init(
        store: LibraryStore, thumbnails: ThumbnailService, waveforms: @escaping () -> WaveformService,
        tuning: PlaybackTuning
    ) {
        self.store = store
        self.thumbnails = thumbnails
        self.waveforms = waveforms
        self.tuning = tuning
        playback = tuning.playback
    }

    // MARK: Selection

    /// Follows the library's selection: the focused file (or the only selected one) is previewed.
    func selectionChanged(_ selection: SelectionModel) {
        selectionCount = selection.selected.count
        let focus = selection.focus.flatMap { selection.contains($0) ? $0 : nil }
            ?? (selection.selected.count == 1 ? selection.selected.first : nil)
        guard focus != focusID else { return }
        focusID = focus
        guard !isSuspended, externalFiles.isEmpty else { return }
        load(focus)
    }

    /// A viewer opened: the previews let go of the player (stopping it unless the viewer now plays in it).
    func suspend(viewerPlays: Bool) {
        isSuspended = true
        loadTask?.cancel()
        if ownsPlayback, !viewerPlays {
            playback.stop()
        }
        ownsPlayback = false
    }

    /// The focused file may have moved or been renamed: load it again.
    func reload() {
        guard !isSuspended else { return }
        if externalFiles.isEmpty {
            load(focusID)
        } else {
            loadExternal()
        }
    }

    /// The viewer closed: show the focused file again, paused.
    func resume() {
        isSuspended = false
        load(focusID)
    }

    // MARK: Quick Preview

    func setQuickPreviewOpen(_ open: Bool) {
        isQuickPreviewOpen = open
        guard ownsPlayback else { return }
        if open, autoplayInPreview {
            playback.play()
        } else if !open {
            playback.pause()
        }
    }

    func togglePlayPause() {
        if sequence != nil {
            toggleSequencePlay()
        } else if ownsPlayback {
            playback.togglePlayPause()
        }
    }

    var isFailed: Bool {
        guard ownsPlayback else { return false }
        if case .failed = playback.status {
            return true
        }
        return false
    }

    // MARK: Loading

    private func load(_ id: Int64?) {
        loadTask?.cancel()
        guard let id else {
            clear()
            return
        }
        loadTask = Task { [weak self, store] in
            let asset = await (try? store.assets(ids: [id]))?.first
            guard let self, !Task.isCancelled else { return }
            guard let asset else {
                clear()
                return
            }
            await show(asset)
        }
    }

    private func clear() {
        endSequence()
        asset = nil
        picture = nil
        cover = nil
        waveform = nil
        if ownsPlayback {
            playback.stop()
            ownsPlayback = false
        }
    }

    private func show(_ asset: Asset) async {
        endSequence()
        self.asset = asset
        picture = nil
        cover = nil
        waveform = nil
        switch asset.kind {
        case .photo:
            if ownsPlayback {
                playback.stop()
                ownsPlayback = false
            }
            if let frames = foldedSequence?(asset.id), frames.count > 1 {
                beginSequence(frames)
            }
            await showPhoto(asset)
        case .video, .audio:
            startPlayer(asset)
            if asset.kind == .audio {
                await showAudioExtras(asset)
            }
        }
    }

    private func showPhoto(_ asset: Asset) async {
        for bucket in [ThumbnailBucket.large, .medium] {
            if let cached = thumbnailService(for: asset).cachedThumbnail(for: request(asset, bucket)), let image = cached {
                picture = image
                break
            }
        }
        let url = asset.url
        let decoded = await Task.detached(priority: .userInitiated) {
            PhotoDecoder.image(at: url, maxPixelSize: Self.photoPixels)
        }.value
        guard !Task.isCancelled, self.asset == asset else { return }
        headPicture = decoded
        // A sequence: the first frame's decode shows only while the first frame does.
        if let decoded, sequence?.index ?? 0 == 0 {
            picture = decoded
        }
    }

    private func startPlayer(_ asset: Asset) {
        tuning.prepare(for: asset.kind)
        playback.loops = false
        playback.autoAdvance = false
        playback.onTimeChange = { [liveTime] seconds in liveTime.seconds = seconds }
        playback.onMotionChange = { [liveTime] rate in liveTime.rate = rate }
        playback.load(
            PlaybackQueue(items: [PlaybackItem(asset: asset)]),
            autoplay: isQuickPreviewOpen && autoplayInPreview
        )
        ownsPlayback = true
    }

    private func showAudioExtras(_ asset: Asset) async {
        cover = await thumbnailService(for: asset).thumbnail(for: request(asset, .large), priority: .visible)
        guard !Task.isCancelled, self.asset == asset else { return }
        let stream = waveforms().waveform(
            for: WaveformRequest(url: asset.url, assetID: asset.id > 0 ? asset.id : nil, modifiedAt: asset.modifiedAt)
        )
        for await partial in stream {
            guard !Task.isCancelled, self.asset == asset else { return }
            waveform = JGWaveformPeaks(
                lows: (0 ..< partial.count).map(partial.low(at:)), highs: (0 ..< partial.count).map(partial.high(at:))
            )
        }
    }

    func request(_ asset: Asset, _ bucket: ThumbnailBucket) -> ThumbnailRequest {
        ThumbnailRequest(
            assetID: asset.id, url: asset.url, kind: asset.kind, typeIdentifier: asset.typeIdentifier,
            modifiedAt: asset.modifiedAt, duration: asset.duration, bucket: bucket
        )
    }
}

// MARK: Files from Finder

extension PreviewModel {
    /// Shows `files` (Finder ▸ Services ▸ Quick Preview) until `endExternal`; the library's focus waits.
    func showExternal(_ files: [URL], index: Int) {
        externalFiles = files
        externalIndex = min(max(index, 0), max(files.count - 1, 0))
        isSuspended = false
        loadExternal()
    }

    /// The folder's media files arrived: the same file stays shown, the arrows now reach its neighbors.
    func replaceExternalFiles(_ files: [URL], keeping current: URL) {
        guard !externalFiles.isEmpty, let index = files.firstIndex(of: current) else { return }
        externalFiles = files
        externalIndex = index
    }

    /// Moves to the previous or next file; false at the ends.
    @discardableResult
    func moveExternal(by offset: Int) -> Bool {
        let target = externalIndex + offset
        guard externalFiles.indices.contains(target) else { return false }
        externalIndex = target
        loadExternal()
        return true
    }

    /// Back to the library's selection.
    func endExternal() {
        guard !externalFiles.isEmpty else { return }
        externalFiles = []
        externalIndex = 0
        load(focusID)
    }

    private func loadExternal() {
        loadTask?.cancel()
        guard externalFiles.indices.contains(externalIndex) else { return }
        let url = externalFiles[externalIndex]
        let id = -Int64(externalIndex + 1)
        loadTask = Task { [weak self, store, classifier] in
            let path = CanonicalPath.of(url)
            let inLibrary = await (try? store.location(of: path, isDirectory: false))??.assetID
            let libraryAsset = if let inLibrary {
                await (try? store.assets(ids: [inLibrary]))?.first
            } else {
                Asset?.none
            }
            let asset = libraryAsset ?? Self.outsideAsset(url, id: id, classifier: classifier)
            guard let self, !Task.isCancelled, let asset else { return }
            await show(asset)
        }
    }

    /// A file outside the library as an asset with a negative id (never stored), from its file attributes.
    nonisolated static func outsideAsset(_ url: URL, id: Int64, classifier: MediaClassifier) -> Asset? {
        guard let type = classifier.classify(fileName: url.lastPathComponent) else { return nil }
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey, .creationDateKey])
        return Asset(
            id: id, folderID: 0, name: url.lastPathComponent, url: url, kind: type.kind, typeIdentifier: type.typeIdentifier,
            size: Int64(values?.fileSize ?? 0), modifiedAt: values?.contentModificationDate ?? .distantPast,
            createdAt: values?.creationDate, width: nil, height: nil, orientation: nil, duration: nil, frameRate: nil,
            codec: nil, capturedAt: nil, state: .present, metadataState: .pending
        )
    }

    /// The library's thumbnails for its assets, a memory-only service for outside files.
    func thumbnailService(for asset: Asset) -> ThumbnailService {
        asset.id > 0 ? thumbnails : outsideThumbnails
    }
}
