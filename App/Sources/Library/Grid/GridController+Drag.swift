import AppKit
import JGModel

/// Dragging tiles (docs/FEATURES.md §7): onto a sidebar folder moves the files (⌥ copies); outside the app only
/// copies are offered, so a drop on Finder never moves the user's file (DECISIONS D-35).
/// True while tiles of this app are being dragged (window-level drop targets ignore them).
@MainActor
enum InternalDrag {
    static var isActive = false
}

extension GridController: NSDraggingSource {
    /// Waits for the mouse: a drag past a few points drags the selection; a plain click on a selected tile in a
    /// multiple selection selects just that tile, like Finder.
    func trackDrag(from event: NSEvent, item id: Int64) {
        let start = event.locationInWindow
        while let next = collectionView.window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if next.type == .leftMouseUp {
                if model.selection.selected.count > 1 {
                    model.selection.select(id)
                    selectionDidChange()
                }
                return
            }
            let distance = hypot(next.locationInWindow.x - start.x, next.locationInWindow.y - start.y)
            if distance > Self.dragThreshold {
                beginDrag(with: next)
                return
            }
        }
    }

    /// Points the mouse must move before a click becomes a drag.
    static let dragThreshold: CGFloat = 4

    private func beginDrag(with event: NSEvent) {
        // A folded image sequence drags all its frames (D-84).
        let ids = model.expandingSequences(
            model.selection.selected.sorted { (model.order.index(of: $0) ?? 0) < (model.order.index(of: $1) ?? 0) }
        )
        let origin = collectionView.convert(event.locationInWindow, from: nil)
        // Only files whose rows are loaded can be dragged (visible and recently shown ones).
        let items: [NSDraggingItem] = ids.compactMap { id in
            guard let url = rows[id]?.url else { return nil }
            let item = NSDraggingItem(pasteboardWriter: url as NSURL)
            let side = layout.targetTileSide / 2
            let frame = NSRect(x: origin.x - side / 2, y: origin.y - side / 2, width: side, height: side)
            item.setDraggingFrame(frame, contents: dragImage(for: id))
            return item
        }
        guard !items.isEmpty else { return }
        InternalDrag.isActive = true
        // The grid takes drops only for reordering an album, so Finder drops still reach the window.
        if model.state.albumID != nil {
            collectionView.registerForDraggedTypes([.fileURL])
        }
        let session = collectionView.beginDraggingSession(with: items, event: event, source: self)
        session.draggingFormation = .pile
        session.animatesToStartingPositionsOnCancelOrFail = true
    }

    private func dragImage(for id: Int64) -> NSImage? {
        guard let index = model.order.index(of: id),
              let item = collectionView.item(at: IndexPath(item: index, section: 0)) as? ThumbnailItem,
              let image = item.tile?.image
        else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: image.width, height: image.height))
    }

    func draggingSession(_: NSDraggingSession, endedAt _: NSPoint, operation _: NSDragOperation) {
        InternalDrag.isActive = false
        collectionView.unregisterDraggedTypes()
        albumDragEnded()
    }

    func draggingSession(_: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        context == .outsideApplication ? .copy : [.move, .copy]
    }
}
