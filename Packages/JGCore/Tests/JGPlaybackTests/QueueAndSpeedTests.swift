import Foundation
import JGModel
import Testing
@testable import JGPlayback

struct PlaybackQueueTests {
    static func items(_ count: Int) -> [PlaybackItem] {
        (0 ..< count).map { PlaybackItem(url: URL(fileURLWithPath: "/tmp/\($0).mp3"), name: "\($0).mp3", kind: .audio) }
    }

    @Test func clampsTheStartIndexAndKnowsItsNeighbors() {
        let queue = PlaybackQueue(items: Self.items(3), index: 7)
        #expect(queue.index == 2)
        #expect(queue.hasPrevious)
        #expect(!queue.hasNext)
        #expect(PlaybackQueue().current == nil)
        #expect(PlaybackQueue(items: Self.items(3), index: -1).index == 0)
    }

    @Test func selectRejectsOutOfRangeAndCurrent() {
        var queue = PlaybackQueue(items: Self.items(3), index: 1)
        let current = queue.select(1)
        let outside = queue.select(3)
        let valid = queue.select(2)
        #expect(!current)
        #expect(!outside)
        #expect(valid)
        #expect(queue.current?.name == "2.mp3")
    }

    @Test func endActionLoopsAdvancesOrStops() {
        let middle = PlaybackQueue(items: Self.items(3), index: 1)
        #expect(middle.endAction(loop: true, autoAdvance: true) == .replay)
        #expect(middle.endAction(loop: false, autoAdvance: true) == .advance(2))
        #expect(middle.endAction(loop: false, autoAdvance: false) == .stop)
        let last = PlaybackQueue(items: Self.items(3), index: 2)
        #expect(last.endAction(loop: false, autoAdvance: true) == .stop)
        #expect(last.endAction(loop: true, autoAdvance: false) == .replay)
    }

    @Test func previousRestartsAfterTheThresholdOrAtTheFirstItem() {
        let middle = PlaybackQueue(items: Self.items(3), index: 1)
        #expect(middle.previousAction(currentTime: 1) == .move(0))
        #expect(middle.previousAction(currentTime: PlaybackQueue.restartThreshold + 0.1) == .restart)
        #expect(PlaybackQueue(items: Self.items(3), index: 0).previousAction(currentTime: 0) == .restart)
    }

    @Test func replacingItemsKeepsTheCurrentOne() {
        var queue = PlaybackQueue(items: [Self.items(3)[1]], index: 0)
        queue.replaceItems(Self.items(3), keeping: queue.current?.id)
        #expect(queue.index == 1)
        queue.replaceItems(Self.items(2).reversed(), keeping: URL(fileURLWithPath: "/tmp/gone.mp3"))
        #expect(queue.index == 0)
    }
}

struct PlaybackSpeedTests {
    @Test func presetsAreAscendingInsideTheRangeAndIncludeNormal() {
        #expect(PlaybackSpeed.presets == PlaybackSpeed.presets.sorted())
        #expect(PlaybackSpeed.presets.contains(PlaybackSpeed.normal))
        #expect(PlaybackSpeed.presets.allSatisfy(PlaybackSpeed.range.contains))
    }

    @Test func clampsToTheRangeAndTheFineStep() {
        #expect(PlaybackSpeed.clamped(10) == PlaybackSpeed.range.upperBound)
        #expect(PlaybackSpeed.clamped(0) == PlaybackSpeed.range.lowerBound)
        #expect(abs(PlaybackSpeed.clamped(1.234) - 1.25) < 0.0001)
    }

    @Test func steppingLandsExactlyOnPresets() {
        var rate = PlaybackSpeed.normal
        for _ in 0 ..< 5 {
            rate = PlaybackSpeed.stepped(rate, by: 1)
        }
        #expect(rate == 1.25)
        #expect(PlaybackSpeed.presets.allSatisfy { PlaybackSpeed.clamped($0) == $0 })
    }

    @Test func repeatedStepsDoNotDrift() {
        var rate = PlaybackSpeed.normal
        for _ in 0 ..< 10 {
            rate = PlaybackSpeed.stepped(rate, by: 1)
        }
        #expect(abs(rate - 1.5) < 0.0001)
        for _ in 0 ..< 100 {
            rate = PlaybackSpeed.stepped(rate, by: -1)
        }
        #expect(rate == PlaybackSpeed.range.lowerBound)
    }

    @Test func volumeFollowsHearingNotAmplitude() {
        #expect(PlaybackController.gain(1) == 1)
        #expect(PlaybackController.gain(0) == 0)
        #expect(PlaybackController.gain(0.5) == 0.125)
        #expect(PlaybackController.gain(2) == 1)
    }
}
