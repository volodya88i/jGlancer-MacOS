import Testing
@testable import JGModel

struct SwipeTrackerTests {
    let both: (Int) -> Bool = { _ in true }

    @Test func instantPagesOncePerGestureAfterTheThreshold() {
        var tracker = SwipeTracker(isAnimated: false)
        #expect(tracker.move(by: -30, canPage: both) == nil)
        #expect(tracker.move(by: -20, canPage: both) == 1)
        // The same gesture does not page again.
        #expect(tracker.move(by: -200, canPage: both) == nil)
        #expect(tracker.end(width: 800, velocity: 0, canPage: both) == nil)
        // Content to the right brings the previous file; a missing neighbor does not page.
        #expect(tracker.move(by: 50, canPage: both) == -1)
        _ = tracker.end(width: 800, velocity: 0, canPage: both)
        #expect(tracker.move(by: 50) { $0 == 1 } == nil)
    }

    @Test func animatedCompletesWhenFarOrFlungAndSpringsBackOtherwise() {
        var tracker = SwipeTracker(isAnimated: true)
        #expect(tracker.move(by: -100, canPage: both) == nil)
        #expect(tracker.offset(canPage: both) == -100)
        // 100 of 800 is short and slow: back.
        #expect(tracker.end(width: 800, velocity: -100, canPage: both) == nil)
        _ = tracker.move(by: -200, canPage: both)
        #expect(tracker.end(width: 800, velocity: 0, canPage: both) == 1)
        // A short flick completes; a flick against the travel does not.
        _ = tracker.move(by: 60, canPage: both)
        #expect(tracker.end(width: 800, velocity: 900, canPage: both) == -1)
        _ = tracker.move(by: 60, canPage: both)
        #expect(tracker.end(width: 800, velocity: -900, canPage: both) == nil)
    }

    @Test func noNeighborMeansResistanceAndNoPage() {
        var tracker = SwipeTracker(isAnimated: true)
        let onlyPrevious: (Int) -> Bool = { $0 == -1 }
        _ = tracker.move(by: -400, canPage: onlyPrevious)
        #expect(tracker.offset(canPage: onlyPrevious) == -400 * SwipeTracker.edgeResistance)
        #expect(tracker.end(width: 800, velocity: -2000, canPage: onlyPrevious) == nil)
    }
}
