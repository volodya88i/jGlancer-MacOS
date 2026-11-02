import Testing
@testable import JGModel

struct SequencePlaybackTests {
    @Test func playsAt24FramesASecondAndStopsAtTheLast() {
        var playback = SequencePlayback(frameCount: 30)
        playback.scrub(to: 10)
        playback.play(at: 100)
        #expect(playback.due(at: 100.5) == 22)
        playback.tick(at: 100.5) { _ in true }
        #expect(playback.index == 22)
        playback.tick(at: 102) { _ in true }
        #expect(playback.index == 29)
        #expect(!playback.isPlaying)
        // At the end, play starts again from the first frame.
        playback.play(at: 200)
        #expect(playback.index == 0)
    }

    @Test func framesNotReadyAreSkippedWithoutSlowingTheClock() {
        var playback = SequencePlayback(frameCount: 90)
        playback.play(at: 0)
        let changed = playback.tick(at: 1.0 / 24 * 3) { $0 != 3 }
        #expect(!changed)
        #expect(playback.index == 0)
        playback.tick(at: 1.0 / 24 * 4 + 0.001) { $0 != 3 }
        #expect(playback.index == 4)
        // The last frame shows when its time comes, ready or not: play ends on it.
        playback.tick(at: 10) { _ in false }
        #expect(playback.index == 89)
        #expect(!playback.isPlaying)
    }

    @Test func scrubbingClampsAndPauses() {
        var playback = SequencePlayback(frameCount: 5)
        playback.play(at: 0)
        playback.scrub(to: 40)
        #expect(playback.index == 4)
        #expect(!playback.isPlaying)
        playback.scrub(to: -3)
        #expect(playback.index == 0)
    }
}
