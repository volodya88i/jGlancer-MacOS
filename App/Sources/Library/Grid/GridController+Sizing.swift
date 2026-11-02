import AppKit
import JGThumbs

/// Live tile-size changes (D-93). A ruler drag changes the size many times a second: the tiles take each size as it
/// comes (no stretching, rows centered), so they grow smoothly instead of jumping when the column count changes; the
/// drag starts from the size shown. A short while after the last change the rows fill again (gliding with Animate the
/// library grid) and thumbnails of the new size are asked for. A single big step (a click on the ruler, a menu
/// command) is not live: the tiles fill at once.
extension GridController {
    /// Steps smaller than this start a live change; while one runs, every step joins it.
    static let liveStepLimit: CGFloat = 24
    /// Quiet time after which a live change settles.
    static let sizingSettleDelay = 0.25

    /// Called by `sync` before anything else: whether this sync is a step of a live size change.
    func beginSizing() -> Bool {
        let old = layout.targetTileSide
        let new = model.state.tileSide
        guard new != old else { return false }
        if layout.liveScale == nil {
            guard abs(new - old) < Self.liveStepLimit, old > 0 else { return false }
            // Start from what is shown: a filled tile is a little bigger than the size set.
            layout.liveScale = layout.currentGeometry().tileSide / old
        }
        sizingSettle?.cancel()
        sizingSettle = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.sizingSettleDelay))
            guard !Task.isCancelled else { return }
            self?.settleSizing()
        }
        return true
    }

    /// The rows fill again (gliding when the grid animates), the anchor tile stays, the new thumbnail size loads.
    func settleSizing() {
        guard layout.liveScale != nil else { return }
        let anchor = reflowAnchor()
        let before = model.animatesGrid ? drawnFrames() : [:]
        layout.liveScale = nil
        collectionView.layoutSubtreeIfNeeded()
        anchor.map(restore)
        if model.animatesGrid {
            glide(from: before)
        }
        let bucket = sizeBucket
        if bucket != currentBucket {
            currentBucket = bucket
            cancelAllThumbnails()
            reconfigureVisibleItems()
        }
        updateWindow()
    }
}
