import AppKit
import JGModel
import JGThumbs

/// Grid reflow (D-83, W-69): when the tile size, the names or the sort change, the visible tiles glide from where
/// they were drawn to their new frames (0.3 s, cubic ease-out) and tiles arriving from off screen fade in. Each
/// change starts from what is on screen at that moment, so dragging the size ruler follows smoothly. A new size keeps
/// the focused tile (or the first one on screen) where it was. Layer animations only: the collection view's own
/// layout is never fought.
extension GridController {
    static let reflowDuration = 0.3

    /// What a sync animates: captured before the change, played after it.
    struct ReflowPlan {
        var animates = false
        var before: [Int64: CGRect] = [:]
        var anchor: (index: Int, offset: CGFloat)?
        var toggled: (head: Int64, unfolded: Bool)?
        var ghosts: [CALayer] = []
    }

    /// Captures the drawn tiles before a sync changes the layout (call before applying the model).
    /// - Parameter liveSizing: the size changes live (a ruler drag): tiles grow on their own, and glide only when the
    ///   column count changes.
    func planReflow(sortChanged: Bool, toggled: (head: Int64, unfolded: Bool)?, liveSizing: Bool) -> ReflowPlan {
        var plan = ReflowPlan()
        let sizeChanged = layout.targetTileSide != model.state.tileSide
        let sizeGlides = sizeChanged && (!liveSizing || columnsChange)
        plan.animates = model.isLoaded && (model.animatesGrid
            && (sizeGlides || layout.showsCaptions != model.state.showNames || sortChanged)
            || toggled != nil && !model.reducesMotion)
        plan.toggled = toggled
        plan.anchor = sizeChanged ? reflowAnchor() : nil
        guard plan.animates else { return plan }
        plan.before = drawnFrames()
        if let toggled, !toggled.unfolded, let sequence = model.sequence(headedBy: toggled.head) {
            plan.ghosts = foldingGhosts(of: sequence)
        }
        return plan
    }

    /// Plays a plan after the sync.
    func finish(_ plan: ReflowPlan) {
        if let anchor = plan.anchor {
            collectionView.layoutSubtreeIfNeeded()
            restore(anchor)
        }
        guard plan.animates else { return }
        let unfolding = plan.toggled.flatMap { $0.unfolded ? model.sequence(headedBy: $0.head) : nil }
        glide(from: plan.before, unfolding: unfolding)
        if let head = plan.toggled?.head {
            flyIn(plan.ghosts, to: head)
        }
    }

    /// Whether the size set gives another column count than shown.
    private var columnsChange: Bool {
        let shown = layout.currentGeometry()
        let next = GridGeometry(
            itemCount: shown.itemCount, width: shown.width, targetTileSide: model.state.tileSide * (layout.liveScale ?? 1),
            gutter: shown.gutter, inset: shown.inset, captionHeight: 0, fillsRow: layout.liveScale == nil
        )
        return next.columns != shown.columns
    }

    /// Where the visible tiles are laid out now, relative to the visible rect. Glides are additive (they move a tile
    /// relative to its laid-out frame), so a running one keeps going on top of the next.
    func drawnFrames() -> [Int64: CGRect] {
        let origin = collectionView.visibleRect.origin
        var frames: [Int64: CGRect] = [:]
        for case let item as ThumbnailItem in collectionView.visibleItems() {
            guard let id = item.assetID else { continue }
            let frame = item.view.frame
            frames[id] = frame.offsetBy(dx: -origin.x, dy: -origin.y)
        }
        return frames
    }

    /// The tile to keep in place across a size change, and its offset from the top of the visible rect.
    func reflowAnchor() -> (index: Int, offset: CGFloat)? {
        let visible = collectionView.visibleRect
        let geometry = layout.currentGeometry()
        let onScreen = geometry.indices(in: visible)
        let focus = model.selection.focus.flatMap { model.order.index(of: $0) }
        guard let index = focus.flatMap({ onScreen.contains($0) ? $0 : nil }) ?? onScreen.first else { return nil }
        return (index, geometry.frame(at: index).minY - visible.minY)
    }

    /// Scrolls so the anchor tile sits where it was.
    func restore(_ anchor: (index: Int, offset: CGFloat)) {
        let geometry = layout.currentGeometry()
        guard anchor.index < geometry.itemCount else { return }
        let clip = scrollView.contentView
        let maxY = max(0, collectionView.frame.height - clip.bounds.height)
        let y = min(max(geometry.frame(at: anchor.index).minY - anchor.offset, 0), maxY)
        clip.scroll(to: NSPoint(x: clip.bounds.origin.x, y: y))
        scrollView.reflectScrolledClipView(clip)
    }

    /// Frames of an unfolding sequence fly out one after another this far apart, none later than `flyLatest`.
    static let flyStagger = 0.012
    static let flyLatest = 0.25

    /// Glides each visible tile from its old frame (`before`, relative to the visible rect) to its new one; the
    /// frames of an unfolding sequence fly out of its head, one after another.
    func glide(from before: [Int64: CGRect], unfolding: ImageSequence? = nil) {
        collectionView.layoutSubtreeIfNeeded()
        let origin = collectionView.visibleRect.origin
        let timing = CAMediaTimingFunction(controlPoints: 0.33, 1, 0.68, 1)
        for case let item as ThumbnailItem in collectionView.visibleItems() {
            guard let id = item.assetID, let layer = item.view.layer else { continue }
            let target = item.view.frame
            var start = before[id]
            var delay = 0.0
            if start == nil, let unfolding, let position = unfolding.frames.firstIndex(of: id), let head = before[unfolding.head] {
                start = head
                delay = min(Double(position) * Self.flyStagger, Self.flyLatest)
            }
            guard let old = start?.offsetBy(dx: origin.x, dy: origin.y), target.width > 0 else {
                let fade = CABasicAnimation(keyPath: "opacity")
                fade.fromValue = 0
                fade.toValue = 1
                fade.duration = Self.reflowDuration
                fade.timingFunction = timing
                layer.add(fade, forKey: "reflow-fade")
                continue
            }
            guard old != target else { continue }
            layer.add(Self.additiveGlide(from: old, to: target, timing: timing, delay: delay, in: layer), forKey: "reflow-\(reflowSerial)")
        }
        reflowSerial &+= 1
    }

    /// An offset from `old` to `target` that decays to nothing: added on top of the layer's own frame, so later
    /// layout changes and later glides combine instead of jumping. Layer-backed views anchor at their origin: the
    /// origin moves, the size scales from it.
    private static func additiveGlide(
        from old: CGRect, to target: CGRect, timing: CAMediaTimingFunction, delay: Double, in layer: CALayer
    ) -> CAAnimationGroup {
        func additive(_ keyPath: String, from value: Any) -> CABasicAnimation {
            let animation = CABasicAnimation(keyPath: keyPath)
            animation.fromValue = value
            animation.toValue = keyPath == "position" ? NSValue(point: .zero) : 0.0
            animation.isAdditive = true
            return animation
        }
        let group = CAAnimationGroup()
        group.animations = [
            additive("position", from: NSValue(point: CGPoint(x: old.minX - target.minX, y: old.minY - target.minY))),
            additive("transform.scale.x", from: old.width / target.width - 1),
            additive("transform.scale.y", from: old.height / max(target.height, 1) - 1),
        ]
        group.duration = reflowDuration
        group.timingFunction = timing
        if delay > 0 {
            group.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
            group.fillMode = .backwards
        }
        return group
    }

    /// Before a sequence folds: its visible frames as pictures over the grid, flying into the head and fading once
    /// the grid has its new layout (`flyIn`).
    func foldingGhosts(of sequence: ImageSequence) -> [CALayer] {
        var ghosts: [CALayer] = []
        for case let item as ThumbnailItem in collectionView.visibleItems() {
            guard let id = item.assetID, id != sequence.head, sequence.frames.contains(id), let tile = item.tile else { continue }
            let ghost = CALayer()
            ghost.contents = tile.image
            ghost.contentsGravity = .resizeAspect
            ghost.frame = tile.imageLayer.convert(tile.imageLayer.bounds, to: collectionView.layer)
            ghost.zPosition = 5
            collectionView.layer?.addSublayer(ghost)
            ghosts.append(ghost)
        }
        return ghosts
    }

    func flyIn(_ ghosts: [CALayer], to head: Int64) {
        guard let index = model.order.index(of: head) else {
            ghosts.forEach { $0.removeFromSuperlayer() }
            return
        }
        let target = layout.currentGeometry().frame(at: index)
        CATransaction.begin()
        CATransaction.setAnimationDuration(Self.reflowDuration)
        CATransaction.setCompletionBlock { ghosts.forEach { $0.removeFromSuperlayer() } }
        for ghost in ghosts {
            ghost.frame = target
            ghost.opacity = 0
        }
        CATransaction.commit()
    }

    /// A thumbnail of another size from memory, to stand in until this size's arrives.
    func standInThumbnail(for asset: Asset) -> CGImage? {
        for bucket in [ThumbnailBucket.large, .medium, .small] where bucket != currentBucket {
            let request = ThumbnailRequest(
                assetID: asset.id, url: asset.url, kind: asset.kind, typeIdentifier: asset.typeIdentifier,
                modifiedAt: asset.modifiedAt, duration: asset.duration, bucket: bucket
            )
            if case let .some(.some(image)) = model.thumbnails.cachedThumbnail(for: request) {
                return image
            }
        }
        return nil
    }
}
