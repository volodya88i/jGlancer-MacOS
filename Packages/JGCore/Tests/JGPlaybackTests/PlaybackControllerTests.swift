import Foundation
import JGModel
import JGTestSupport
import Testing
@testable import JGPlayback

/// Plays real generated files through AVFoundation; slow-ish (each item lasts a fraction of a second).
@MainActor
@Suite(.serialized)
struct PlaybackControllerTests {
    let directory: TemporaryDirectory
    let items: [PlaybackItem]

    init() throws {
        let directory = try TemporaryDirectory()
        self.directory = directory
        items = try (0 ..< 3).map { index in
            let url = directory.url.appendingPathComponent("tone\(index).wav")
            try MediaFactory.wav(at: url, seconds: 0.4)
            return PlaybackItem(url: url, name: url.lastPathComponent, kind: .audio)
        }
    }

    @Test func playsAndAdvancesToTheNextItemAtTheEnd() async throws {
        let controller = PlaybackController()
        controller.load(PlaybackQueue(items: items, index: 0))
        #expect(try await until(timeout: .seconds(5)) { controller.status == .ready })
        #expect(abs((controller.duration ?? 0) - 0.4) < 0.05)
        #expect(controller.info?.hasVideo == false)
        #expect(try await until(timeout: .seconds(5)) { controller.queue.index == 1 })
        controller.stop()
        #expect(controller.status == .idle)
    }

    @Test func loopsTheCurrentItem() async throws {
        let controller = PlaybackController()
        controller.loops = true
        controller.load(PlaybackQueue(items: items, index: 0))
        try await Task.sleep(for: .seconds(1.2))
        #expect(controller.queue.index == 0)
        #expect(controller.isPlaying)
        controller.stop()
    }

    @Test func stopsAtTheEndWithoutAutoAdvance() async throws {
        let controller = PlaybackController()
        controller.autoAdvance = false
        controller.load(PlaybackQueue(items: items, index: 2))
        #expect(try await until(timeout: .seconds(5)) { controller.status == .ready && !controller.isPlaying })
        #expect(controller.queue.index == 2)
        #expect(abs(controller.currentTime - 0.4) < 0.05)
    }

    @Test func appliesTheRateWhilePlayingAndClampsIt() async throws {
        let controller = PlaybackController()
        controller.loops = true
        controller.load(PlaybackQueue(items: items, index: 0))
        #expect(try await until(timeout: .seconds(5)) { controller.isPlaying })
        controller.setRate(1.5)
        #expect(controller.player.rate == 1.5)
        controller.setRate(100)
        #expect(controller.rate == PlaybackSpeed.range.upperBound)
        controller.pause()
        #expect(try await until(timeout: .seconds(2)) { !controller.isPlaying })
        controller.stop()
    }

    @Test func scrubbingMutesWithoutChangingTheUsersMute() {
        let controller = PlaybackController()
        controller.mutesWhileScrubbing = true
        #expect(controller.player.isMuted)
        #expect(!controller.isMuted)
        controller.mutesWhileScrubbing = false
        #expect(!controller.player.isMuted)
        controller.isMuted = true
        controller.mutesWhileScrubbing = false
        #expect(controller.player.isMuted)
    }

    @Test func reportsTheMotionRateWhilePlaying() async throws {
        let controller = PlaybackController()
        controller.isMuted = true
        var rates: [Double] = []
        controller.onMotionChange = { rates.append($0) }
        controller.load(PlaybackQueue(items: items))
        #expect(try await until(timeout: .seconds(5)) { controller.isPlaying })
        controller.pause()
        #expect(try await until(timeout: .seconds(2)) { !controller.isPlaying })
        #expect(rates.first == 1)
        #expect(rates.last == 0)
        controller.stop()
    }

    @Test func timeUpdatesFollowThePlayheadSpeed() {
        let controller = PlaybackController()
        // 3 minutes over 900 points: 0.2 s per point.
        #expect(abs(controller.timeUpdateInterval(duration: 180, width: 900) - 0.2) < 0.0001)
        // A short clip on a wide scrubber is capped at the display rate, a long film at four updates a second.
        #expect(controller.timeUpdateInterval(duration: 10, width: 1900) == PlaybackController.maximumUpdateRate)
        #expect(controller.timeUpdateInterval(duration: 7200, width: 900) == PlaybackController.minimumUpdateRate)
        #expect(controller.timeUpdateInterval(duration: nil, width: 900) == PlaybackController.maximumUpdateRate)
        controller.setRate(2)
        #expect(abs(controller.timeUpdateInterval(duration: 180, width: 900) - 0.1) < 0.0001)
    }

    @Test func reportsUnplayableFiles() async throws {
        let fake = try directory.write("fake.mkv", "not a video")
        let controller = PlaybackController()
        controller.load(PlaybackQueue(items: [PlaybackItem(url: fake, name: "fake.mkv", kind: .video)]))
        #expect(try await until(timeout: .seconds(5)) {
            if case .failed = controller.status {
                true
            } else {
                false
            }
        })
        controller.play()
        #expect(!controller.isPlaying)
    }

    @Test func previousRestartsOrGoesBack() {
        let controller = PlaybackController()
        controller.autoAdvance = false
        controller.load(PlaybackQueue(items: items, index: 1), autoplay: false)
        controller.previous()
        #expect(controller.queue.index == 0)
        controller.previous()
        #expect(controller.queue.index == 0)
        controller.stop()
    }
}

/// Polls a main-actor `condition` until it holds or `timeout` passes.
@MainActor
func until(timeout: Duration, _ condition: () -> Bool) async throws -> Bool {
    let deadline = ContinuousClock.now + timeout
    while ContinuousClock.now < deadline {
        if condition() {
            return true
        }
        try await Task.sleep(for: .milliseconds(20))
    }
    return condition()
}

struct MediaInfoTests {
    @Test func readsVideoSizeAndAudioTags() async throws {
        let directory = try TemporaryDirectory()
        let movie = directory.url.appendingPathComponent("clip.mov")
        try await MediaFactory.mov(at: movie, width: 64, height: 48, frames: 10, fps: 10)
        let video = try await MediaInfo.load(.init(url: movie))
        #expect(video.isPlayable)
        #expect(video.videoSize == CGSize(width: 64, height: 48))
        #expect(abs((video.duration ?? 0) - 1) < 0.15)
        let sound = directory.url.appendingPathComponent("tone.wav")
        try MediaFactory.wav(at: sound, seconds: 0.2)
        let audio = try await MediaInfo.load(.init(url: sound))
        #expect(audio.isPlayable)
        #expect(!audio.hasVideo)
    }
}
