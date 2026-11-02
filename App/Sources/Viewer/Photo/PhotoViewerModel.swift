import CoreGraphics
import Foundation
import JGModel
import JGScanner
import JGStore
import JGThumbs
import Observation
import os

/// One photo the viewer can show.
struct ViewerPhoto: Hashable, Sendable {
    let url: URL
    let name: String
    /// Set for library assets (selection on return, cached thumbnail as placeholder).
    let assetID: Int64?
    let modifiedAt: Date?
    let typeIdentifier: String?
}

/// The photo viewer's state (docs/ARCHITECTURE.md §8): the folder context, the current index, a pager that keeps
/// the current photo and ±2 neighbors decoded at screen size, and full resolution for the current one on zoom.
@MainActor
@Observable
final class PhotoViewerModel {
    /// A position in the folder context: a library asset (rows load lazily) or a file outside the library.
    enum Entry: Hashable, Sendable {
        case asset(Int64)
        case file(ViewerPhoto)
    }

    /// A decoded image with the photo's full pixel size (orientation applied).
    struct Picture: Equatable {
        let image: CGImage
        let fullSize: CGSize
        let isFullResolution: Bool
        /// The grid thumbnail standing in until the screen-size decode arrives.
        var isPlaceholder = false
    }

    private(set) var entries: [Entry]
    private(set) var index: Int
    /// What is shown now: the best picture available for the current photo (nil while nothing is ready).
    private(set) var picture: Picture? {
        didSet { updateShownPicture() }
    }

    /// `picture` turned by `quarterTurns` for viewing only (the file is never changed).
    private(set) var shownPicture: Picture?
    /// Quarter turns clockwise of the current photo; back to 0 on the next photo.
    private(set) var quarterTurns = 0
    @ObservationIgnored private var rotationTask: Task<Void, Never>?
    /// True when the current photo could not be decoded.
    private(set) var failed = false
    /// Folder of a file opened from outside the library, offered for adding (nil inside the library).
    private(set) var folderToOffer: URL?
    var isHUDVisible = true
    /// Milliseconds from the last navigation to its picture being shown (benchmarks, signpost `viewer.next`).
    private(set) var lastNavigationMilliseconds: Double?

    private let store: LibraryStore?
    let thumbnails: ThumbnailService?
    /// Longest side, in pixels, of screen-size decodes.
    let screenPixels: Int
    var rows: [Int64: ViewerPhoto] = [:]
    /// Held while the current photo decodes, so background metadata reading waits (D-82).
    private let decodeGate: PauseGate?
    /// Rows already requested (an asset deleted meanwhile must not be requested forever).
    private var requestedRows: Set<Int64> = []
    private var decoded: [Entry: Picture] = [:]
    private var decodeTasks: [Entry: Task<Void, Never>] = [:]
    private var fullTask: Task<Void, Never>?
    private var navigationStart: (date: Date, state: OSSignpostIntervalState)?
    private let signposter = OSSignposter(subsystem: "jGlancer.app", category: "viewer")
    /// The library's thumbnails, or a memory-only service for files outside the library (filmstrip).
    @ObservationIgnored let filmstripThumbnails: ThumbnailService
    /// Stand-in ids for files outside the library (keys of the private thumbnail service).
    @ObservationIgnored private var outsideIDs: [URL: Int64] = [:]

    init(
        entries: [Entry], index: Int, store: LibraryStore?, thumbnails: ThumbnailService?,
        screenPixels: Int, folderToOffer: URL? = nil, opened: ViewerPhoto? = nil, decodeGate: PauseGate? = nil
    ) {
        self.decodeGate = decodeGate
        self.entries = entries
        self.index = Pager.move(index, by: 0, count: entries.count)
        self.store = store
        self.thumbnails = thumbnails
        filmstripThumbnails = thumbnails ?? ThumbnailService(disk: nil, memoryLimitBytes: 8 * 1024 * 1024)
        self.screenPixels = screenPixels
        self.folderToOffer = folderToOffer
        // The opened photo's row is known: its thumbnail shows and its decode starts at once (D-82).
        if let opened, let id = opened.assetID {
            rows[id] = opened
        }
        refresh()
    }

    // MARK: Navigation

    var count: Int {
        entries.count
    }

    var currentPhoto: ViewerPhoto? {
        entries.indices.contains(index) ? photo(for: entries[index]) : nil
    }

    func move(by offset: Int) {
        let target = Pager.move(index, by: offset, count: entries.count)
        guard target != index else { return }
        navigationStart = (Date(), signposter.beginInterval("viewer.next"))
        lastNavigationMilliseconds = nil
        index = target
        quarterTurns = 0
        refresh()
    }

    /// Turns the view by quarter turns (positive: clockwise), for viewing only.
    func rotate(by turns: Int) {
        quarterTurns = ((quarterTurns + turns) % 4 + 4) % 4
        updateShownPicture()
    }

    private func updateShownPicture() {
        rotationTask?.cancel()
        guard let picture, quarterTurns != 0 else {
            shownPicture = picture
            return
        }
        let turns = quarterTurns
        let image = picture.image
        rotationTask = Task { [weak self] in
            let rotated = await Task.detached(priority: .userInitiated) { Self.rotated(image, quarterTurns: turns) }.value
            guard let self, !Task.isCancelled, let rotated else { return }
            let size = turns.isMultiple(of: 2) ? picture.fullSize : CGSize(width: picture.fullSize.height, height: picture.fullSize.width)
            shownPicture = Picture(
                image: rotated, fullSize: size, isFullResolution: picture.isFullResolution, isPlaceholder: picture.isPlaceholder
            )
        }
    }

    /// `image` turned clockwise by `quarterTurns` × 90°.
    nonisolated static func rotated(_ image: CGImage, quarterTurns: Int) -> CGImage? {
        let odd = !quarterTurns.isMultiple(of: 2)
        let width = odd ? image.height : image.width
        let height = odd ? image.width : image.height
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: image.colorSpace ?? CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        context.translateBy(x: CGFloat(width) / 2, y: CGFloat(height) / 2)
        context.rotate(by: -CGFloat(quarterTurns) * .pi / 2)
        context.draw(
            image,
            in: CGRect(
                x: -CGFloat(image.width) / 2,
                y: -CGFloat(image.height) / 2,
                width: CGFloat(image.width),
                height: CGFloat(image.height)
            )
        )
        return context.makeImage()
    }

    /// Drops the current photo (it went to the Trash) and shows the next one, or the previous at the end.
    /// Returns false when nothing is left.
    func removeCurrent() -> Bool {
        guard entries.indices.contains(index) else { return false }
        let removed = entries.remove(at: index)
        decoded[removed] = nil
        guard !entries.isEmpty else { return false }
        index = min(index, entries.count - 1)
        refresh()
        return true
    }

    /// Replaces the context once a folder listing arrives, keeping the photo at `url` current and on screen.
    func replaceEntries(_ newEntries: [Entry], keeping url: URL) {
        let previous = entries.indices.contains(index) ? entries[index] : nil
        entries = newEntries
        index = newEntries.firstIndex { photo(for: $0)?.url.path == url.path } ?? 0
        if let previous, let ready = decoded[previous], entries.indices.contains(index) {
            decoded[entries[index]] = ready
        }
        refresh()
    }

    func dismissFolderOffer() {
        folderToOffer = nil
    }

    // MARK: Pager

    /// Shows the best available picture for the current photo and keeps ±2 neighbors decoding.
    private func refresh() {
        failed = false
        fullTask?.cancel()
        fullTask = nil
        let window = Pager.window(around: index, count: entries.count).map { entries[$0] }
        let keep = Set(window)
        for (entry, task) in decodeTasks where !keep.contains(entry) {
            task.cancel()
            decodeTasks[entry] = nil
        }
        decoded = decoded.filter { keep.contains($0.key) }
        loadRows(for: window)
        let current = entries.indices.contains(index) ? entries[index] : nil
        if let current, let ready = decoded[current] {
            show(ready)
        } else {
            picture = placeholder(for: current)
            if picture == nil, let current {
                loadPlaceholder(for: current)
            }
        }
        for (order, entry) in window.enumerated() where decoded[entry] == nil && decodeTasks[entry] == nil {
            decode(entry, priority: order == 0 ? .userInitiated : .utility)
        }
    }

    private func show(_ ready: Picture) {
        picture = ready
        if let start = navigationStart {
            signposter.endInterval("viewer.next", start.state)
            lastNavigationMilliseconds = Date().timeIntervalSince(start.date) * 1000
            navigationStart = nil
        }
    }

    /// A stand-in picture, unless a decoded one is already shown.
    func standIn(_ placeholder: Picture) {
        if picture == nil {
            picture = placeholder
        }
    }

    private func decode(_ entry: Entry, priority: TaskPriority) {
        guard let photo = photo(for: entry) else { return }
        let url = photo.url
        let pixels = screenPixels
        let gate = priority == .userInitiated ? decodeGate : nil
        decodeTasks[entry] = Task { [weak self] in
            await gate?.hold()
            let result = await Task.detached(priority: priority) { () -> Picture? in
                guard let size = PhotoDecoder.displaySize(of: url),
                      let image = PhotoDecoder.image(at: url, maxPixelSize: pixels)
                else { return nil }
                return Picture(
                    image: image, fullSize: size,
                    isFullResolution: CGFloat(image.width) >= size.width && CGFloat(image.height) >= size.height
                )
            }.value
            await gate?.release()
            guard let self, !Task.isCancelled else { return }
            decodeTasks[entry] = nil
            let isCurrent = entries.indices.contains(index) && entries[index] == entry
            if let result {
                decoded[entry] = result
                if isCurrent {
                    show(result)
                }
            } else if isCurrent {
                failed = true
            }
        }
    }

    /// Decodes the current photo at full resolution (called when zoomed beyond fit).
    func requestFullResolution() {
        guard fullTask == nil, let picture, !picture.isFullResolution, let photo = currentPhoto else { return }
        let entry = entries[index]
        let url = photo.url
        fullTask = Task { [weak self] in
            let image = await Task.detached(priority: .userInitiated) { PhotoDecoder.fullResolution(at: url) }.value
            guard let self, !Task.isCancelled, let image, entries.indices.contains(index), entries[index] == entry else { return }
            self.picture = Picture(image: image, fullSize: picture.fullSize, isFullResolution: true)
        }
    }

    // MARK: Rows

    func photo(for entry: Entry) -> ViewerPhoto? {
        switch entry {
        case let .file(photo): photo
        case let .asset(id): rows[id]
        }
    }

    /// Loads library rows around the current index (one query), then continues decoding.
    private func loadRows(for window: [Entry]) {
        let missing = window.compactMap { entry -> Int64? in
            if case let .asset(id) = entry, rows[id] == nil, !requestedRows.contains(id) {
                return id
            }
            return nil
        }
        guard !missing.isEmpty, let store else { return }
        let extra = entries.indices.contains(index)
            ? entries[max(0, index - 10) ..< min(entries.count, index + 11)].compactMap { entry -> Int64? in
                if case let .asset(id) = entry, rows[id] == nil, !requestedRows.contains(id) {
                    return id
                }
                return nil
            }
            : []
        requestedRows.formUnion(missing + extra)
        Task { [weak self] in
            let assets = await (try? store.assets(ids: Array(Set(missing + extra)))) ?? []
            guard let self else { return }
            for asset in assets {
                rows[asset.id] = ViewerPhoto(
                    url: asset.url, name: asset.name, assetID: asset.id, modifiedAt: asset.modifiedAt,
                    typeIdentifier: asset.typeIdentifier
                )
            }
            // Only rows the pager is waiting for restart it (filmstrip rows must not drop a full-size picture).
            let pagerWindow = Set(Pager.window(around: index, count: entries.count).map { entries[$0] })
            if assets.contains(where: { pagerWindow.contains(.asset($0.id)) }) {
                refresh()
            }
        }
    }
}

extension PhotoViewerModel: FilmstripSource {
    var filmstripCount: Int {
        entries.count
    }

    var filmstripIndex: Int {
        index
    }

    func filmstripItem(at position: Int) -> FilmstripItem? {
        guard entries.indices.contains(position), let photo = photo(for: entries[position]) else { return nil }
        return FilmstripItem(
            name: photo.name, kind: .photo,
            thumbnail: ThumbnailRequest(
                assetID: photo.assetID ?? outsideID(for: photo.url), url: photo.url, kind: .photo,
                typeIdentifier: photo.typeIdentifier, modifiedAt: photo.modifiedAt ?? .distantPast, duration: nil,
                bucket: .small
            )
        )
    }

    /// Library rows load in batches around tiles coming on screen.
    func filmstripPrepare(around position: Int) {
        guard entries.indices.contains(position) else { return }
        loadRows(for: Array(entries[max(0, position - 20) ..< min(entries.count, position + 21)]))
    }

    func filmstripSelect(_ position: Int) {
        move(by: position - index)
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

/// Neighbors for swiping.
extension PhotoViewerModel {
    /// The decoded picture of the photo `offset` places away (swipe animation), if it is ready.
    func neighborPicture(by offset: Int) -> Picture? {
        let position = index + offset
        return entries.indices.contains(position) ? decoded[entries[position]] : nil
    }

    func canMove(by offset: Int) -> Bool {
        entries.indices.contains(index + offset)
    }
}
