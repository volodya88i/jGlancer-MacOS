import AppKit
import JGDesign

/// Reordering an album by dragging its tiles within the grid (docs/FEATURES.md §6): a thin accent bar marks where
/// they will land; only the app's own drags count, and only while the grid shows an album.
extension GridController {
    /// Where a drag at `point` would insert: the id to land in front of (nil: the end) and the bar's frame.
    private func albumDropTarget(at point: NSPoint) -> (before: Int64?, bar: NSRect)? {
        guard model.state.albumID != nil, InternalDrag.isActive, !model.refs.isEmpty else { return nil }
        let geometry = layout.currentGeometry()
        let barWidth = JGMetrics.selectionEdgeWidth
        guard let index = geometry.index(at: point), index < model.refs.count else {
            let last = collectionView.frameForItem(at: model.refs.count - 1)
            return (nil, NSRect(x: last.maxX + JGMetrics.gridGutter / 2 - barWidth / 2, y: last.minY, width: barWidth, height: last.width))
        }
        let frame = collectionView.frameForItem(at: index)
        let after = point.x > frame.midX
        let landing = after ? index + 1 : index
        let x = after ? frame.maxX + JGMetrics.gridGutter / 2 : frame.minX - JGMetrics.gridGutter / 2
        let before = landing < model.refs.count ? model.refs[landing].id : nil
        return (before, NSRect(x: x - barWidth / 2, y: frame.minY, width: barWidth, height: frame.width))
    }

    func albumDragUpdated(_ info: NSDraggingInfo) -> NSDragOperation {
        let point = collectionView.convert(info.draggingLocation, from: nil)
        guard let target = albumDropTarget(at: point) else {
            dropIndicator.isHidden = true
            return []
        }
        if dropIndicator.superlayer == nil {
            collectionView.layer?.addSublayer(dropIndicator)
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        dropIndicator.backgroundColor = JGColor.accent.nsColor.cgColor
        dropIndicator.frame = target.bar
        dropIndicator.isHidden = false
        CATransaction.commit()
        return .move
    }

    func albumDragEnded() {
        dropIndicator.isHidden = true
    }

    func performAlbumDrop(_ info: NSDraggingInfo) -> Bool {
        dropIndicator.isHidden = true
        let point = collectionView.convert(info.draggingLocation, from: nil)
        guard let target = albumDropTarget(at: point) else { return false }
        let moving = model.selection.selected.sorted { (model.order.index(of: $0) ?? 0) < (model.order.index(of: $1) ?? 0) }
        guard !moving.isEmpty, target.before.map({ !moving.contains($0) }) ?? true else { return false }
        Task { await model.reorderCurrentAlbum(moving, before: target.before) }
        return true
    }
}
