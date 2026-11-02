import AppKit

/// Mouse, wheel and trackpad input of `ScrubberView`: seeking, dragging a segment's ends, zooming and scrolling.
public extension ScrubberView {
    // MARK: Seeking and segment ends

    override func mouseDown(with event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        if let edge = segmentEdge(near: x) {
            draggedEdge = edge
            dragEdge(to: x, isFinal: false)
            return
        }
        isScrubbing = true
        scrub(event, isFinal: false)
    }

    override func mouseDragged(with event: NSEvent) {
        if draggedEdge != nil {
            dragEdge(to: convert(event.locationInWindow, from: nil).x, isFinal: false)
        } else {
            scrub(event, isFinal: false)
        }
    }

    override func mouseUp(with event: NSEvent) {
        if draggedEdge != nil {
            dragEdge(to: convert(event.locationInWindow, from: nil).x, isFinal: true)
            draggedEdge = nil
            return
        }
        scrub(event, isFinal: true)
        isScrubbing = false
    }

    private func scrub(_ event: NSEvent, isFinal: Bool) {
        guard duration > 0 else { return }
        let x = convert(event.locationInWindow, from: nil).x
        scrubTime = visible.time(at: x, width: max(bounds.width, 1))
        placePlayhead()
        onSeek?(scrubTime, isFinal)
    }

    /// The segment end within reach of `x`, the nearer one when both are.
    internal func segmentEdge(near x: CGFloat) -> JGSegmentEdge? {
        guard let segment, duration > 0 else { return nil }
        let reach = JGMetrics.segmentEdgeReach
        let toStart = abs(x - self.x(of: segment.lowerBound))
        let toEnd = abs(x - self.x(of: segment.upperBound) - JGMetrics.selectionEdgeWidth)
        guard min(toStart, toEnd) <= reach else { return nil }
        return toStart < toEnd || (toStart == toEnd && x < self.x(of: segment.lowerBound)) ? .start : .end
    }

    private func dragEdge(to x: CGFloat, isFinal: Bool) {
        guard let edge = draggedEdge, let current = segment else { return }
        let time = visible.time(at: x, width: max(bounds.width, 1))
        let gap = min(Self.minimumSegment, duration)
        let moved = switch edge {
        case .start: min(max(time, 0), current.upperBound - gap) ... current.upperBound
        case .end: current.lowerBound ... max(min(time, duration), current.lowerBound + gap)
        }
        segment = moved
        onSegmentChange?(moved, edge, isFinal)
    }

    /// A right click inside the segment: its menu.
    override func menu(for event: NSEvent) -> NSMenu? {
        guard let segment, let segmentMenu, duration > 0 else { return super.menu(for: event) }
        let time = visible.time(at: convert(event.locationInWindow, from: nil).x, width: max(bounds.width, 1))
        return segment.contains(time) ? segmentMenu() : super.menu(for: event)
    }

    // MARK: Zoom and scroll

    /// ⌘-wheel (the wheel alone with `wheelZooms`) or vertical trackpad scroll zooms around the pointer; ⇧-wheel, ⇧-vertical or horizontal
    /// scroll
    /// moves the window. Other scrolling goes on to the views behind.
    override func scrollWheel(with event: NSEvent) {
        guard allowsZoom, duration > 0, bounds.width > 0 else {
            super.scrollWheel(with: event)
            return
        }
        let precise = event.hasPreciseScrollingDeltas
        let horizontal = event.scrollingDeltaX
        let vertical = event.scrollingDeltaY
        let shift = event.modifierFlags.contains(.shift)
        let command = event.modifierFlags.contains(.command)
        // Points for a trackpad, lines for a wheel.
        let unit: CGFloat = precise ? 1 : JGMetrics.wheelLinePoints
        if command || ((precise || wheelZooms) && !shift && abs(vertical) > abs(horizontal)) {
            // Up (pushing away, whatever the scrolling direction setting) zooms in.
            let upward = event.isDirectionInvertedFromDevice ? -vertical : vertical
            zoom(by: exp(Double(upward * unit) * JGMetrics.zoomPerPoint), at: event)
        } else if shift || abs(horizontal) > abs(vertical) {
            let delta = abs(horizontal) >= abs(vertical) ? horizontal : vertical
            visible.scroll(by: -Double(delta * unit / bounds.width) * visible.length)
            windowDidChange()
        } else {
            super.scrollWheel(with: event)
        }
    }

    /// Pinch to zoom.
    override func magnify(with event: NSEvent) {
        guard allowsZoom, duration > 0 else {
            super.magnify(with: event)
            return
        }
        zoom(by: 1 + Double(event.magnification), at: event)
    }

    private func zoom(by factor: Double, at event: NSEvent) {
        let anchor = visible.time(at: convert(event.locationInWindow, from: nil).x, width: bounds.width)
        let before = visible
        visible.zoom(by: factor, around: anchor)
        if visible != before {
            windowDidChange()
        }
    }
}
