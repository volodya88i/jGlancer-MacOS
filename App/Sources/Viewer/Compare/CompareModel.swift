import CoreGraphics
import Foundation
import JGModel
import JGStore
import JGThumbs
import Observation

/// Compare (W-77): two photos side by side. Each side shows its thumbnail at once, then a screen-size decode, then
/// full resolution once zoomed past fit. Linked (the default), both sides share one zoom kept as fractions, so photos
/// of different sizes show the same part; unlinked, each side has its own. Zoom keys act on the focused side.
@MainActor
@Observable
final class CompareModel {
    /// One photo of the pair.
    struct Side: Identifiable {
        let asset: Asset
        /// Pixel size after orientation (0 until read).
        var pixelSize: CGSize = .zero
        var image: CGImage?
        var isFullResolution = false
        var id: Int64 {
            asset.id
        }
    }

    /// Keys and buttons: zoom keys act on the focused side.
    enum Key {
        case fit, actualSize, zoomIn, zoomOut, toggleLink, swap
    }

    private(set) var sides: [Side]
    var isLinked = true
    /// The side zoom keys act on: the one clicked or scrolled last.
    var focusedSide = 0
    /// The shared zoom while linked, and each side's own.
    private(set) var linkedZoom = CompareZoom()
    private(set) var ownZooms = [CompareZoom(), CompareZoom()]

    @ObservationIgnored private let thumbnails: ThumbnailService
    @ObservationIgnored private let screenPixels: Int
    @ObservationIgnored private var tasks: [Int64: Task<Void, Never>] = [:]
    /// Each side's view bounds and backing scale, reported by its canvas.
    @ObservationIgnored private var layouts: [(bounds: CGRect, scale: CGFloat)] = [(.zero, 2), (.zero, 2)]
    private static let keyStep: CGFloat = 1.25

    init(assets: [Asset], thumbnails: ThumbnailService, screenPixels: Int) {
        sides = assets.prefix(2).map { Side(asset: $0, pixelSize: Self.storedSize(of: $0)) }
        self.thumbnails = thumbnails
        self.screenPixels = screenPixels
        for index in sides.indices {
            load(index)
        }
    }

    func close() {
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
    }

    /// The left photo, selected in the library on the way back.
    var leftAssetID: Int64? {
        sides.first?.asset.id
    }

    func zoom(of side: Int) -> CompareZoom {
        isLinked ? linkedZoom : ownZooms[side]
    }

    /// Changes the zoom of `side` (both while linked) with its picture's size at 100 % and its view's bounds; full
    /// resolution is decoded past fit.
    func changeZoom(of side: Int, _ change: (inout CompareZoom, _ actualSize: CGSize, _ bounds: CGRect) -> Void) {
        focusedSide = side
        let layout = layouts[side]
        let pixels = sides[side].pixelSize
        let actual = CGSize(width: pixels.width / layout.scale, height: pixels.height / layout.scale)
        if isLinked {
            change(&linkedZoom, actual, layout.bounds)
        } else {
            change(&ownZooms[side], actual, layout.bounds)
        }
        for index in sides.indices where !zoom(of: index).isFit {
            loadFullResolution(index)
        }
    }

    func setLayout(of side: Int, bounds: CGRect, backingScale: CGFloat) {
        layouts[side] = (bounds, backingScale)
    }

    func apply(_ key: Key) {
        switch key {
        case .toggleLink: toggleLink()
        case .swap: swap()
        case .fit: changeZoom(of: focusedSide) { zoom, _, _ in zoom.reset() }
        case .actualSize:
            changeZoom(of: focusedSide) { zoom, size, bounds in
                zoom.zoom(to: CompareZoom.actualScale(of: size, in: bounds.size), at: nil, actualSize: size, in: bounds)
            }
        case .zoomIn: changeZoom(of: focusedSide) { $0.zoom(by: Self.keyStep, at: nil, actualSize: $1, in: $2) }
        case .zoomOut: changeZoom(of: focusedSide) { $0.zoom(by: 1 / Self.keyStep, at: nil, actualSize: $1, in: $2) }
        }
    }

    /// L: unlinked sides keep the zoom they showed; linking again takes the focused side's.
    func toggleLink() {
        if isLinked {
            ownZooms = [linkedZoom, linkedZoom]
        } else {
            linkedZoom = ownZooms[focusedSide]
        }
        isLinked.toggle()
    }

    /// X: the photos change places.
    func swap() {
        sides.reverse()
        ownZooms.reverse()
        focusedSide = 1 - focusedSide
    }

    // MARK: Loading

    private func load(_ index: Int) {
        let asset = sides[index].asset
        let url = asset.url
        let pixels = screenPixels
        tasks[asset.id] = Task { [weak self, thumbnails] in
            if let thumbnail = await Self.thumbnail(of: asset, thumbnails: thumbnails) {
                self?.update(asset.id) { side in
                    if side.image == nil {
                        side.image = thumbnail
                        if side.pixelSize == .zero {
                            // Unknown size: the thumbnail's shape at screen size, until the decode tells.
                            let scale = CGFloat(pixels) / CGFloat(max(thumbnail.width, thumbnail.height, 1))
                            side.pixelSize = CGSize(width: CGFloat(thumbnail.width) * scale, height: CGFloat(thumbnail.height) * scale)
                        }
                    }
                }
            }
            let decoded = await Task.detached(priority: .userInitiated) { () -> (CGSize, CGImage)? in
                guard let size = PhotoDecoder.displaySize(of: url), let image = PhotoDecoder.image(at: url, maxPixelSize: pixels)
                else { return nil }
                return (size, image)
            }.value
            self?.tasks[asset.id] = nil
            guard !Task.isCancelled, let decoded else { return }
            self?.update(asset.id) { side in
                side.pixelSize = decoded.0
                if !side.isFullResolution {
                    side.image = decoded.1
                    side.isFullResolution = CGFloat(decoded.1.width) >= decoded.0.width
                }
            }
        }
    }

    private func loadFullResolution(_ index: Int) {
        let side = sides[index]
        // After the screen-size decode (which also tells the true size), once.
        guard !side.isFullResolution, side.image != nil, tasks[side.id] == nil else { return }
        let url = side.asset.url
        let id = side.id
        sides[index].isFullResolution = true
        tasks[id]?.cancel()
        tasks[id] = Task { [weak self] in
            let image = await Task.detached(priority: .userInitiated) { PhotoDecoder.fullResolution(at: url) }.value
            guard !Task.isCancelled, let image else { return }
            self?.update(id) { $0.image = image }
        }
    }

    /// The size the library read, turned by the EXIF orientation (5–8 swap the sides).
    private static func storedSize(of asset: Asset) -> CGSize {
        guard let width = asset.width, let height = asset.height else { return .zero }
        let turned = (5 ... 8).contains(asset.orientation ?? 1)
        return turned ? CGSize(width: height, height: width) : CGSize(width: width, height: height)
    }

    private func update(_ id: Int64, _ change: (inout Side) -> Void) {
        guard let index = sides.firstIndex(where: { $0.id == id }) else { return }
        change(&sides[index])
    }

    /// The largest thumbnail in memory or on disk.
    private static func thumbnail(of asset: Asset, thumbnails: ThumbnailService) async -> CGImage? {
        let requests = [ThumbnailBucket.large, .medium, .small].map { bucket in
            ThumbnailRequest(
                assetID: asset.id, url: asset.url, kind: .photo, typeIdentifier: asset.typeIdentifier,
                modifiedAt: asset.modifiedAt, duration: nil, bucket: bucket
            )
        }
        for request in requests {
            if let cached = thumbnails.cachedThumbnail(for: request), let image = cached {
                return image
            }
        }
        for request in requests {
            if let image = await thumbnails.storedThumbnail(for: request) {
                return image
            }
        }
        return nil
    }
}
