import AppKit
import JGDesign
import JGModel

/// Selection input of the grid: click, ⌘-click, ⇧-click, marquee with autoscroll, keyboard moves.
extension GridController {
    func mouseDown(_ event: NSEvent) {
        model.onInteraction?()
        let point = collectionView.convert(event.locationInWindow, from: nil)
        let geometry = layout.currentGeometry()
        let modifiers = event.modifierFlags
        if let index = geometry.index(at: point), index < model.refs.count {
            let id = model.refs[index].id
            // A sequence's badge, or a double-click on its head, folds or unfolds it (D-84).
            if model.sequence(headedBy: id) != nil, modifiers.isDisjoint(with: [.command, .shift]),
               event.clickCount == 2 || isOnSequenceBadge(point, index: index)
            {
                model.toggleSequence(id)
                return
            }
            // ⌥-double-click plays songs in the window's mini player (D-88).
            if event.clickCount == 2, modifiers.contains(.option), model.refs[index].kind == .audio {
                model.selection.select(id)
                selectionDidChange()
                model.onPlayInMiniPlayer?(id)
                return
            }
            if event.clickCount == 2, !modifiers.contains(.command), !modifiers.contains(.shift) {
                model.selection.select(id)
                selectionDidChange()
                model.open(id)
                return
            }
            if modifiers.contains(.command) {
                model.selection.toggle(id)
            } else if modifiers.contains(.shift) {
                model.selection.extend(to: id, in: model.order)
            } else if !model.selection.contains(id) {
                model.selection.select(id)
            }
            selectionDidChange()
            if modifiers.isDisjoint(with: [.command, .shift]) {
                trackDrag(from: event, item: id)
            }
            return
        }
        trackMarquee(from: point, adding: modifiers.contains(.command) || modifiers.contains(.shift))
    }

    private func isOnSequenceBadge(_ point: CGPoint, index: Int) -> Bool {
        guard let item = collectionView.item(at: IndexPath(item: index, section: 0)) as? ThumbnailItem,
              let tile = item.tile, let badge = tile.sequenceBadgeFrame
        else { return false }
        return badge.contains(tile.convert(point, from: collectionView))
    }

    /// Classic AppKit tracking loop: drag a rectangle (autoscrolling) until the mouse is released.
    private func trackMarquee(from start: CGPoint, adding: Bool) {
        model.selection.beginMarquee(adding: adding)
        selectionDidChange()
        if marqueeLayer.superlayer == nil {
            collectionView.layer?.addSublayer(marqueeLayer)
        }
        var lastHit: Int64?
        while let event = collectionView.window?.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]) {
            if event.type == .leftMouseUp {
                break
            }
            collectionView.autoscroll(with: event)
            let current = collectionView.convert(event.locationInWindow, from: nil)
            let rect = CGRect(
                x: min(start.x, current.x), y: min(start.y, current.y),
                width: abs(current.x - start.x), height: abs(current.y - start.y)
            )
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            marqueeLayer.isHidden = false
            marqueeLayer.frame = rect
            CATransaction.commit()
            let refs = model.refs
            let ids = layout.currentGeometry().indices(intersecting: rect).filter { $0 < refs.count }.map { refs[$0].id }
            lastHit = ids.last
            model.selection.marquee(ids)
            selectionDidChange()
        }
        marqueeLayer.isHidden = true
        model.selection.commitMarquee(focus: lastHit)
        selectionDidChange()
    }

    func move(_ move: GridMove, extending: Bool) {
        let geometry = layout.currentGeometry()
        guard geometry.itemCount > 0 else { return }
        let current = model.selection.focus.flatMap { model.order.index(of: $0) }
        let rowsPerPage = geometry.rowsPerPage(viewportHeight: collectionView.visibleRect.height)
        let target = current.map { geometry.index(from: $0, moving: move, rowsPerPage: rowsPerPage) }
            ?? (move == .end ? geometry.itemCount - 1 : 0)
        let id = model.refs[target].id
        if extending {
            model.selection.extend(to: id, in: model.order)
        } else {
            model.selection.select(id)
        }
        selectionDidChange()
        scrollToVisible(target)
    }

    /// Return: opens the focused item.
    func openFocused() {
        if let focus = model.selection.focus {
            model.open(focus)
        }
    }

    func selectAll() {
        model.selection.selectAll(model.order)
        selectionDidChange()
    }

    /// Right-click: an unselected item becomes the selection first (as in Finder); empty space has no menu.
    func contextMenu(for event: NSEvent) -> NSMenu? {
        let point = collectionView.convert(event.locationInWindow, from: nil)
        guard let index = layout.currentGeometry().index(at: point), index < model.refs.count else { return nil }
        let id = model.refs[index].id
        if !model.selection.contains(id) {
            model.selection.select(id)
            selectionDidChange()
        }
        guard let target = model.actionTarget(sample: rows[id]?.url) else { return nil }
        return model.makeContextMenu?(target)
    }

    func clearSelection() {
        model.selection.clear()
        selectionDidChange()
    }

    func selectionDidChange() {
        lastSelection = model.selection
        refreshSelection()
    }

    func scrollToVisible(_ index: Int) {
        let frame = layout.currentGeometry().frame(at: index).insetBy(dx: 0, dy: -JGMetrics.gridGutter)
        collectionView.scrollToVisible(frame)
        // Back from a viewer the collection view may not lay out for the new position by itself (seen with the
        // automatic filmstrip): the tiles stayed where they were, off screen, until the next scroll.
        collectionView.collectionViewLayout?.invalidateLayout()
        collectionView.layoutSubtreeIfNeeded()
    }
}

extension GridController {
    static func kindName(_ kind: MediaKind) -> String {
        switch kind {
        case .photo: String(localized: "Photo")
        case .video: String(localized: "Video")
        case .audio: String(localized: "Audio")
        }
    }
}
