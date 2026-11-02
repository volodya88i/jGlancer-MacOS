import AVFoundation
import Foundation
import JGTestSupport
import Testing
@testable import JGMatroska

struct MatroskaFileTests {
    /// A 1-second H.264 movie (30 frames) and a 2-second AAC file.
    func sources(in folder: TemporaryDirectory) async throws -> (video: MatroskaTestWriter.Track, audio: MatroskaTestWriter.Track) {
        let movie = folder.url.appendingPathComponent("clip.mov")
        try await MediaFactory.mov(at: movie, width: 64, height: 48, frames: 30, fps: 30)
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
        return try await (
            MatroskaTestWriter.videoTrack(from: movie),
            MatroskaTestWriter.audioTrack(from: song, audioSpecificConfig: MatroskaCodecs.audioSpecificConfig(fromCookie:))
        )
    }

    @Test(arguments: [MatroskaTestWriter.Lacing.none, .xiph, .fixed, .ebml])
    func tracksPacketsAndCues(lacing: MatroskaTestWriter.Lacing) async throws {
        let folder = try TemporaryDirectory()
        let (video, audio) = try await sources(in: folder)
        let url = folder.url.appendingPathComponent("test.mkv")
        try MatroskaTestWriter.write([video, audio], to: url, lacing: lacing, title: "Test")
        let file = try MatroskaFile(url: url)
        #expect(file.title == "Test")
        #expect(file.tracks.map(\.codecID) == ["V_MPEG4/ISO/AVC", "A_AAC"])
        #expect(file.tracks[0].width == 64 && file.tracks[0].height == 48)
        #expect(file.tracks[1].sampleRate == 44100 && file.tracks[1].channels == 2)
        #expect(abs((file.duration ?? 0) - 2) < 0.1)
        #expect(file.cues.count >= 2)
        var reader = file.packets(from: file.clusterOffset(before: 0))
        var videoFrames: [Data] = []
        var audioFrames: [Data] = []
        var firstVideoIsKey: Bool?
        while let packet = reader.next() {
            if packet.track == 1 {
                firstVideoIsKey = firstVideoIsKey ?? packet.isKeyframe
                videoFrames += packet.frames
            } else {
                audioFrames += packet.frames
            }
        }
        #expect(videoFrames == video.samples.map(\.data))
        #expect(firstVideoIsKey == true)
        if lacing == .fixed {
            #expect(audioFrames.count == audio.samples.count)
        } else {
            #expect(audioFrames == audio.samples.map(\.data))
        }
        #expect(MatroskaCodecs.formatDescription(for: file.tracks[0]) != nil)
        #expect(MatroskaCodecs.formatDescription(for: file.tracks[1]) != nil)
    }

    @Test func withoutCuesClustersAreScannedAndSeekingStartsAtTheRightOne() async throws {
        let folder = try TemporaryDirectory()
        let (video, audio) = try await sources(in: folder)
        let url = folder.url.appendingPathComponent("nocues.mkv")
        try MatroskaTestWriter.write([video, audio], to: url, cues: false)
        let file = try MatroskaFile(url: url)
        #expect(file.cues.map(\.time) == [0, 1, 2].filter { $0 <= (file.duration ?? 0) + 0.01 })
        var reader = file.packets(from: file.clusterOffset(before: 1.5))
        #expect((reader.next()?.time ?? 0) >= 1)
    }

    @Test func notMatroskaAndAACConfig() throws {
        let folder = try TemporaryDirectory()
        let url = try folder.write("fake.mkv", "not a matroska file")
        #expect(throws: MatroskaError.self) { try MatroskaFile(url: url) }
        let config = Data([0x12, 0x10])
        #expect(MatroskaCodecs.audioSpecificConfig(fromCookie: MatroskaCodecs.esds(audioSpecificConfig: config)) == config)
        #expect(MatroskaCodecs.lowComplexityConfig(sampleRate: 44100, channels: 2) == config)
    }

    @Test func aThumbnailComesFromAKeyframe() async throws {
        let folder = try TemporaryDirectory()
        let (video, audio) = try await sources(in: folder)
        let url = folder.url.appendingPathComponent("thumb.mkv")
        try MatroskaTestWriter.write([video, audio], to: url)
        let image = try #require(MatroskaThumbnail.image(at: url, maxPixelSize: 32))
        #expect(max(image.width, image.height) == 32)
    }
}
