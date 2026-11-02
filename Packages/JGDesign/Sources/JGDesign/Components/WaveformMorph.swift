import AppKit
import QuartzCore

/// The waveform's entrance (D-79, W-82): a change morphs from the shape on screen into the new one, column by
/// column from left to right — each column takes `columnDuration` with an ease-out-back, the last one starting
/// `spread` after the first. A change during a morph starts from what is drawn at that moment. Frames come from a
/// display link that runs only while morphing.
@MainActor
final class WaveformMorph {
    static let columnDuration = 0.45
    static let spread = 0.27
    static let overshoot = 1.4

    /// What is drawn now.
    private(set) var shown = WaveColumns(tops: [], bottoms: [])
    private var from = WaveColumns(tops: [], bottoms: [])
    private var to = WaveColumns(tops: [], bottoms: [])
    private var start: CFTimeInterval = 0
    private var link: CADisplayLink?

    var isRunning: Bool {
        link != nil
    }

    /// Shows `target` at once (no animation, or a different number of columns).
    func jump(to target: WaveColumns) {
        stop()
        shown = target
    }

    /// Morphs into `target`, calling `view`'s `selector` every frame until done.
    func morph(to target: WaveColumns, view: NSView, selector: Selector) {
        guard target.tops.count == shown.tops.count, target != shown else {
            jump(to: target)
            return
        }
        if isRunning {
            shown = frame(at: CACurrentMediaTime())
        }
        from = shown
        to = target
        start = CACurrentMediaTime()
        if link == nil {
            let link = view.displayLink(target: view, selector: selector)
            link.add(to: .main, forMode: .common)
            self.link = link
        }
    }

    /// Advances to now; false when the morph is over.
    func step() -> Bool {
        let now = CACurrentMediaTime()
        shown = frame(at: now)
        if now - start >= Self.spread + Self.columnDuration {
            shown = to
            stop()
            return false
        }
        return true
    }

    func stop() {
        link?.invalidate()
        link = nil
    }

    /// The shape at `time`: each column eased from `from` to `to` after its delay.
    func frame(at time: CFTimeInterval) -> WaveColumns {
        let count = to.tops.count
        guard count > 1, from.tops.count == count else { return to }
        let elapsed = time - start
        var result = to
        for column in 0 ..< count {
            let delay = Double(column) / Double(count - 1) * Self.spread
            let progress = min(max((elapsed - delay) / Self.columnDuration, 0), 1)
            let eased = CGFloat(Self.easeOutBack(progress))
            result.tops[column] = from.tops[column] + (to.tops[column] - from.tops[column]) * eased
            result.bottoms[column] = from.bottoms[column] + (to.bottoms[column] - from.bottoms[column]) * eased
        }
        return result
    }

    /// Overshoots a little past 1 and settles there.
    static func easeOutBack(_ progress: Double) -> Double {
        let shifted = progress - 1
        return 1 + (overshoot + 1) * shifted * shifted * shifted + overshoot * shifted * shifted
    }
}
