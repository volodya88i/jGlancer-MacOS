import AppKit
import QuartzCore

/// Smooth playhead motion (D-77, W-67): between the player's time reports the playhead moves on with the playback
/// rate, redrawn every display frame by a display link that runs only while playing and on screen. A report that is
/// a little behind the shown time does not pull the playhead back; a jump (a seek) is followed at once.
@MainActor
final class PlayheadMotion {
    /// Seconds per second; 0 while paused.
    private(set) var rate = 0.0
    private var reported = 0.0
    private var reportedAt: CFTimeInterval = 0
    private var shown = 0.0
    private var link: CADisplayLink?
    /// A report this far from the shown time is a seek, not drift.
    static let jump = 0.25

    /// The time to draw now.
    var time: Double {
        guard rate > 0, link != nil else { return reported }
        let predicted = reported + (CACurrentMediaTime() - reportedAt) * rate
        shown = predicted < shown && shown - predicted < Self.jump ? shown : predicted
        return shown
    }

    func report(_ time: Double) {
        if abs(time - shown) >= Self.jump || rate == 0 {
            shown = time
        }
        reported = time
        reportedAt = CACurrentMediaTime()
    }

    /// Starts or stops the frame updates of `view` (calling `tick` each frame) for `rate` and its visibility.
    func update(rate newRate: Double, view: NSView, onScreen: Bool, selector: Selector) {
        if newRate != rate {
            reported = time
            reportedAt = CACurrentMediaTime()
            rate = newRate
        }
        if rate > 0, onScreen {
            guard link == nil else { return }
            let link = view.displayLink(target: view, selector: selector)
            link.add(to: .main, forMode: .common)
            self.link = link
        } else {
            link?.invalidate()
            link = nil
        }
    }
}
