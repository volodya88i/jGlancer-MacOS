import CoreGraphics
import Foundation

/// The part of the timeline a scrubber shows: all of it, or a zoomed window `start` … `start + length` that the
/// user zooms and scrolls (segment selection, docs/DECISIONS.md D-73).
struct ScrubberWindow: Equatable {
    private(set) var duration: Double
    private(set) var start: Double
    private(set) var length: Double

    /// The shortest window, in seconds (or the whole file when it is shorter).
    static let minimumLength = 0.5

    init(duration: Double) {
        self.duration = max(duration, 0)
        start = 0
        length = self.duration
    }

    var end: Double {
        start + length
    }

    var isZoomed: Bool {
        length < duration - 0.000_001
    }

    var range: ClosedRange<Double> {
        start ... end
    }

    /// The x of `time` in `width` points; outside 0…width when the time is outside the window.
    func x(of time: Double, width: CGFloat) -> CGFloat {
        guard length > 0 else { return 0 }
        return CGFloat((time - start) / length) * width
    }

    /// The time at `x` in `width` points, within the file.
    func time(at x: CGFloat, width: CGFloat) -> Double {
        guard width > 0 else { return start }
        return min(max(start + Double(x / width) * length, 0), duration)
    }

    /// Zooms in (`factor` > 1) or out keeping `anchor` at the same place on screen.
    mutating func zoom(by factor: Double, around anchor: Double) {
        guard duration > 0, factor > 0, factor.isFinite else { return }
        let fraction = length > 0 ? (anchor - start) / length : 0
        length = min(max(length / factor, min(Self.minimumLength, duration)), duration)
        start = anchor - fraction * length
        clampStart()
    }

    mutating func scroll(by seconds: Double) {
        guard seconds.isFinite else { return }
        start += seconds
        clampStart()
    }

    /// Moves the window so `time` shows near its left edge (the playhead ran past the right edge).
    mutating func page(to time: Double) {
        start = time - length * 0.1
        clampStart()
    }

    private mutating func clampStart() {
        start = min(max(start, 0), max(duration - length, 0))
    }
}
