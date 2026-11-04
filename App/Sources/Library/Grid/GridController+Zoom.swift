import AppKit
import JGDesign

/// Sizing the tiles with gestures (D-112): a pinch, or ⌘ with two fingers up and down (⌘ and the wheel). Each event
/// is a small step, so it runs as a live size change like a drag of the ruler (D-93).
extension GridController {
    /// Finger travel, in points, that sweeps the whole size range (as on the ruler).
    static let zoomScrollTravel: CGFloat = 300

    /// A pinch of `magnification` (the system's fraction: 0.1 = 10 % larger).
    func zoomTiles(by magnification: CGFloat) {
        setTileSide(model.state.tileSide * (1 + magnification))
    }

    /// ⌘ and scrolling: fingers up enlarge, whatever the "natural scrolling" setting; a wheel notch is half a ruler tick.
    func zoomTiles(scrolling event: NSEvent) {
        let span = JGMetrics.tileSideRange.upperBound - JGMetrics.tileSideRange.lowerBound
        if event.hasPreciseScrollingDeltas {
            let fingersUp = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
            setTileSide(model.state.tileSide + Double(fingersUp) * span / Self.zoomScrollTravel)
        } else if event.scrollingDeltaY != 0 {
            setTileSide(model.state.tileSide + (event.scrollingDeltaY > 0 ? 1 : -1) * JGMetrics.tileSideStep / 2)
        }
    }

    private func setTileSide(_ side: Double) {
        let range = JGMetrics.tileSideRange
        let clamped = min(max(side, range.lowerBound), range.upperBound)
        guard clamped != model.state.tileSide else { return }
        model.setTileSide(clamped)
    }
}
