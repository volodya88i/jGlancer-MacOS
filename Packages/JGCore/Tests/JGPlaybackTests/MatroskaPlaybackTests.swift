import AVFoundation
import Foundation
import JGMatroska
import JGModel
import JGTestSupport
import Testing
@testable import JGPlayback

/// MKV through the controller: H.264 + AAC packed by the test writer, played by the system decoders (muted).
@MainActor
@Suite(.serialized)
struct MatroskaPlaybackTests {
    func makeMKV(in folder: TemporaryDirectory) async throws -> URL {
        let movie = folder.url.appendingPathComponent("clip.mov")
        try await MediaFactory.mov(at: movie, width: 640, height: 360, frames: 60, fps: 30)
        let song = folder.url.appendingPathComponent("tone.m4a")
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2]
        do {
            let file = try AVAudioFile(forWriting: song, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 88200))
            buffer.frameLength = 88200
            try file.write(from: buffer)
            if #available(macOS 15, *) {
                file.close()
            }
        }
        let url = folder.url.appendingPathComponent("clip.mkv")
        try await MatroskaTestWriter.write([
            // `JG_MKV_VIDEO=<H.264 movie>` packs that picture instead of the blank one (for looking at it in the app).
            MatroskaTestWriter.videoTrack(
                from: ProcessInfo.processInfo.environment["JG_MKV_VIDEO"].map { URL(fileURLWithPath: $0) } ?? movie
            ),
            MatroskaTestWriter.audioTrack(from: song, audioSpecificConfig: MatroskaCodecs.audioSpecificConfig(fromCookie:)),
        ], to: url)
        // For checks in the app: `JG_MKV_OUT=<path> swift test …` keeps a copy.
        if let out = ProcessInfo.processInfo.environment["JG_MKV_OUT"] {
            try? FileManager.default.removeItem(atPath: out)
            try FileManager.default.copyItem(at: url, to: URL(fileURLWithPath: out))
        }
        return url
    }

    @Test func playsSeeksAndEnds() async throws {
        let folder = try TemporaryDirectory()
        let url = try await makeMKV(in: folder)
        let controller = PlaybackController()
        controller.isMuted = true
        controller.load(PlaybackQueue(items: [PlaybackItem(url: url, name: "clip.mkv", kind: .video)]))
        #expect(try await until(timeout: .seconds(5)) { controller.status == .ready })
        #expect(controller.info?.videoSize == CGSize(width: 640, height: 360))
        #expect(abs((controller.duration ?? 0) - 2) < 0.1)
        #expect(controller.matroskaLayer != nil)
        try await Task.sleep(for: .milliseconds(600))
        #expect(controller.mediaSeconds > 0.3)
        controller.pause()
        controller.seek(to: 1.5)
        #expect(abs(controller.mediaSeconds - 1.5) < 0.05)
        controller.play()
        #expect(try await until(timeout: .seconds(3)) { !controller.isPlaying })
        #expect(controller.currentTime >= 1.9)
        controller.stop()
        #expect(controller.matroskaLayer == nil)
    }

    /// A visible scrubber keeps a time observer across items: the player's and the engine's, each removed by what added it.
    @Test func timeUpdatesFollowSwitchesBetweenPlayerAndEngine() async throws {
        let folder = try TemporaryDirectory()
        let url = try await makeMKV(in: folder)
        let movie = folder.url.appendingPathComponent("clip.mov")
        let controller = PlaybackController()
        controller.isMuted = true
        controller.beginTimeUpdates()
        controller.load(PlaybackQueue(items: [
            PlaybackItem(url: movie, name: "clip.mov", kind: .video), PlaybackItem(url: url, name: "clip.mkv", kind: .video),
        ]))
        #expect(try await until(timeout: .seconds(5)) { controller.status == .ready })
        controller.select(1)
        #expect(try await until(timeout: .seconds(5)) { controller.status == .ready && controller.matroska != nil })
        #expect(try await until(timeout: .seconds(3)) { controller.currentTime >= 1 })
        controller.select(0)
        #expect(try await until(timeout: .seconds(5)) { controller.status == .ready && controller.matroska == nil })
        #expect(try await until(timeout: .seconds(3)) { controller.currentTime >= 1 })
        controller.endTimeUpdates()
        controller.stop()
    }

    @Test func pausesAtTheStopTime() async throws {
        let folder = try TemporaryDirectory()
        let url = try await makeMKV(in: folder)
        let movie = folder.url.appendingPathComponent("clip.mov")
        for file in [movie, url] {
            let controller = PlaybackController()
            controller.isMuted = true
            controller.load(PlaybackQueue(items: [PlaybackItem(url: file, name: file.lastPathComponent, kind: .video)]))
            #expect(try await until(timeout: .seconds(5)) { controller.status == .ready })
            controller.stopTime = 0.6
            #expect(try await until(timeout: .seconds(3)) { !controller.isPlaying })
            #expect(abs(controller.mediaSeconds - 0.6) < 0.05, "\(file.lastPathComponent): \(controller.mediaSeconds)")
            controller.stop()
        }
    }

    @Test func aFileWithoutPlayableTracksFails() async throws {
        let folder = try TemporaryDirectory()
        let url = try folder.write("broken.mkv", "not matroska")
        let controller = PlaybackController()
        controller.load(PlaybackQueue(items: [PlaybackItem(url: url, name: "broken.mkv", kind: .video)]))
        #expect(try await until(timeout: .seconds(5)) { controller.status == .failed(.unreadable) })
    }
}
