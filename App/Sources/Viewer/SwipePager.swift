import AppKit
import JGDesign
import JGModel
import Observation
import SwiftUI

/// One step of a horizontal swipe from a viewer's AppKit surface: a mouse drag or a two-finger trackpad swipe
/// (mouse wheels never page through this).
enum SwipeInput {
    case began
    /// The content moved by `delta` points (negative: left) at `time` (event timestamp).
    case moved(delta: CGFloat, time: TimeInterval)
    case ended

    /// How far a trackpad scroll event moves the content horizontally, the same with or without natural scrolling.
    static func contentDelta(of event: NSEvent) -> CGFloat {
        event.isDirectionInvertedFromDevice ? event.scrollingDeltaX : -event.scrollingDeltaX
    }
}

/// Paging by swipes in the photo and audio viewers (Settings → Appearance → Show the next file while swiping).
/// Without the animation a swipe turns the page at once; with it the content follows the pointer, the neighbor
/// comes in from the edge, and the release completes or springs back. Reduce Motion always pages at once.
@MainActor
@Observable
final class SwipePager {
    /// The content's horizontal offset while it follows the pointer.
    private(set) var offset: CGFloat = 0
    @ObservationIgnored var width: CGFloat = 0
    @ObservationIgnored var isAnimated = false {
        didSet { tracker = SwipeTracker(isAnimated: isAnimated) }
    }

    /// Whether there is a file in a direction (+1 next, -1 previous), and the move to it.
    @ObservationIgnored var canPage: (Int) -> Bool = { _ in false }
    @ObservationIgnored var page: (Int) -> Void = { _ in }

    @ObservationIgnored private var tracker = SwipeTracker(isAnimated: false)
    @ObservationIgnored private var isTracking = false
    @ObservationIgnored private var isSettling = false
    @ObservationIgnored private var velocity: Double = 0
    @ObservationIgnored private var lastTime: TimeInterval?

    /// The neighbor beside the content while it is off center: +1 next, -1 previous, 0 none.
    var neighbor: Int {
        guard offset != 0 else { return 0 }
        let direction = offset < 0 ? 1 : -1
        return canPage(direction) ? direction : 0
    }

    func handle(_ input: SwipeInput) {
        guard !isSettling else { return }
        switch input {
        case .began:
            start()
        case let .moved(delta, time):
            if !isTracking {
                start()
            }
            track(delta, at: time)
        case .ended:
            finish()
        }
    }

    private func start() {
        isTracking = true
        velocity = 0
        lastTime = nil
        tracker = SwipeTracker(isAnimated: isAnimated)
    }

    private func track(_ delta: CGFloat, at time: TimeInterval) {
        if let lastTime, time > lastTime {
            // Smoothed, so one jittery event does not decide a flick.
            velocity = velocity * 0.6 + Double(delta) / (time - lastTime) * 0.4
        }
        lastTime = time
        if let direction = tracker.move(by: Double(delta), canPage: canPage) {
            page(direction)
        }
        if isAnimated {
            offset = CGFloat(tracker.offset(canPage: canPage))
        }
    }

    private func finish() {
        guard isTracking else { return }
        isTracking = false
        guard let direction = tracker.end(width: Double(width), velocity: velocity, canPage: canPage) else {
            if offset != 0 {
                withAnimation(.spring(duration: JGMetrics.swipeSettleDuration)) { offset = 0 }
            }
            return
        }
        isSettling = true
        withAnimation(.easeOut(duration: JGMetrics.swipeSettleDuration)) {
            offset = CGFloat(-direction) * width
        } completion: { [weak self] in
            guard let self else { return }
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                page(direction)
                offset = 0
            }
            isSettling = false
        }
    }
}
