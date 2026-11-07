import AVFoundation
import Foundation
import JGModel
import JGTestSupport
import Testing
@testable import JGPlayback

struct SegmentExporterTests {
    @Test func namesTheFileByItsRangeAndSpeed() {
        var request = SegmentExportRequest(source: URL(fileURLWithPath: "/m/Song.mp3"), kind: .audio, range: 62 ... 75.44)
        #expect(SegmentExporter.suggestedName(for: request) == "Song (1m02.0s–1m15.4s).m4a")
        request.rate = 1.25
        #expect(SegmentExporter.suggestedName(for: request) == "Song (1m02.0s–1m15.4s) 1.25x.m4a")
        let clip = SegmentExportRequest(source: URL(fileURLWithPath: "/m/clip.MP4"), kind: .video, range: 0 ... 3)
        #expect(SegmentExporter.suggestedName(for: clip) == "clip (0m00.0s–0m03.0s).mp4")
        #expect(SegmentExporter.fileExtension(for: SegmentExportRequest(
            source: URL(fileURLWithPath: "/m/a.avi"), kind: .video, range: 0 ... 1
        )) == "mov")
        #expect(!SegmentExporter.canExport(URL(fileURLWithPath: "/m/a.mkv"), kind: .video))
    }

    @Test func wholeFilesAreNamedBySpeedAndVideoIsCopied() async throws {
        var song = SegmentExportRequest.whole(URL(fileURLWithPath: "/m/Song.flac"), kind: .audio, duration: 200)
        #expect(SegmentExporter.suggestedName(for: song) == "Song.flac")
        song.rate = 1.25
        #expect(SegmentExporter.suggestedName(for: song) == "Song 1.25x.flac")
        #expect(SegmentExporter.canExportWhole(URL(fileURLWithPath: "/m/a.M4V"), kind: .video))
        #expect(!SegmentExporter.canExportWhole(URL(fileURLWithPath: "/m/a.avi"), kind: .video))
        #expect(!SegmentExporter.canExportWhole(URL(fileURLWithPath: "/m/a.mka"), kind: .audio))
        let folder = try TemporaryDirectory()
        let movie = folder.url.appendingPathComponent("clip.mov")
        try await MediaFactory.mov(at: movie, width: 32, height: 32, frames: 30, fps: 30)
        let out = folder.url.appendingPathComponent("copy.mov")
        try await SegmentExporter.export(.whole(movie, kind: .video, duration: 1), to: out)
        #expect(try Data(contentsOf: out) == Data(contentsOf: movie))
    }

    @Test func savingNeverReplacesAFile() async throws {
        let folder = try TemporaryDirectory()
        let movie = folder.url.appendingPathComponent("clip.mov")
        try await MediaFactory.mov(at: movie, width: 32, height: 32, frames: 30, fps: 30)
        let request = SegmentExportRequest(source: movie, kind: .video, range: 0 ... 0.5)
        let wanted = folder.url.appendingPathComponent("cut.mov")
        try Data("keep".utf8).write(to: wanted)
        let saved = try await SegmentExporter.save(request, to: wanted)
        #expect(saved.lastPathComponent == "cut 2.mov")
        #expect(try String(contentsOf: wanted, encoding: .utf8) == "keep")
        #expect(try await SegmentExporter.save(request, to: wanted).lastPathComponent == "cut 3.mov")
    }

    @Test func cutsAVideoWithoutReencoding() async throws {
        let folder = try TemporaryDirectory()
        let movie = folder.url.appendingPathComponent("clip.mov")
        try await MediaFactory.mov(at: movie, width: 64, height: 64, frames: 60, fps: 30)
        let out = folder.url.appendingPathComponent("cut.mov")
        try await SegmentExporter.export(SegmentExportRequest(source: movie, kind: .video, range: 0.5 ... 1.5), to: out)
        let asset = AVURLAsset(url: out)
        #expect(try await abs(asset.load(.duration).seconds - 1) < 0.05)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let codec = try await track.load(.formatDescriptions).first.map(CMFormatDescriptionGetMediaSubType)
        let sourceTrack = try #require(try await AVURLAsset(url: movie).loadTracks(withMediaType: .video).first)
        #expect(try await codec == (sourceTrack.load(.formatDescriptions).first.map(CMFormatDescriptionGetMediaSubType)))
    }

    @Test func cutsAVideoExactlyByEncodingIt() async throws {
        let folder = try TemporaryDirectory()
        let movie = folder.url.appendingPathComponent("clip.mov")
        try await MediaFactory.mov(at: movie, width: 64, height: 64, frames: 60, fps: 30)
        var request = SegmentExportRequest(source: movie, kind: .video, range: 0.4 ... 1.3)
        request.isExact = true
        #expect(SegmentExporter.suggestedName(for: request) == "clip (0m00.4s–0m01.3s).mp4")
        let out = folder.url.appendingPathComponent("exact.mp4")
        try await SegmentExporter.export(request, to: out)
        let asset = AVURLAsset(url: out)
        #expect(try await abs(asset.load(.duration).seconds - 0.9) < 0.05)
        let track = try #require(try await asset.loadTracks(withMediaType: .video).first)
        let codec = try await track.load(.formatDescriptions).first.map(CMFormatDescriptionGetMediaSubType)
        #expect(codec == kCMVideoCodecType_H264)
    }

    @Test func losslessSourcesKeepTheirFormat() async throws {
        let folder = try TemporaryDirectory()
        // 44.1 kHz, 16 bit (the system does not read back FLAC at 8 kHz, the rate of `MediaFactory.wav`).
        let wav = folder.url.appendingPathComponent("tone.wav")
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1,
            AVLinearPCMBitDepthKey: 16, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
        ]
        do {
            let file = try AVAudioFile(forWriting: wav, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 44100 * 3))
            buffer.frameLength = 44100 * 3
            try file.write(from: buffer)
            if #available(macOS 15, *) {
                file.close()
            }
        }
        var request = SegmentExportRequest(source: wav, kind: .audio, range: 1 ... 2)
        #expect(SegmentExporter.fileExtension(for: request) == "wav")
        let sameWav = folder.url.appendingPathComponent("cut.wav")
        try await SegmentExporter.export(request, to: sameWav)
        let pcm = try AVAudioFile(forReading: sameWav)
        #expect(pcm.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatLinearPCM)
        #expect(pcm.fileFormat.streamDescription.pointee.mBitsPerChannel == 16)
        #expect(abs(Double(pcm.length) / pcm.fileFormat.sampleRate - 1) < 0.01)
        // FLAC in, FLAC out.
        let flac = folder.url.appendingPathComponent("cut.flac")
        try await SegmentExporter.export(request, to: flac)
        let flacRequest = SegmentExportRequest(source: flac, kind: .audio, range: 0.25 ... 0.75)
        #expect(SegmentExporter.fileExtension(for: flacRequest) == "flac")
        let again = folder.url.appendingPathComponent("again.flac")
        try await SegmentExporter.export(flacRequest, to: again)
        let decoded = try AVAudioFile(forReading: again)
        #expect(decoded.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatFLAC)
        #expect(abs(Double(decoded.length) / decoded.fileFormat.sampleRate - 0.5) < 0.01)
        request.keepsAudioFormat = false
        #expect(SegmentExporter.fileExtension(for: request) == "m4a")
    }

    /// 20 s of tone, loud for the first 10: 9…11 s at 2× is one second, loud then silent, fading in from silence.
    @Test func exportsAudioWithSpeedAndFadesAsLosslessM4A() async throws {
        let folder = try TemporaryDirectory()
        let wav = folder.url.appendingPathComponent("tone.wav")
        try MediaFactory.wav(at: wav, seconds: 20, amplitude: 0.8, loudSeconds: 10)
        var request = SegmentExportRequest(source: wav, kind: .audio, range: 9 ... 11)
        request.rate = 2
        request.fades = true
        request.keepsAudioFormat = false
        let out = folder.url.appendingPathComponent("cut.m4a")
        try await SegmentExporter.export(request, to: out)
        let file = try AVAudioFile(forReading: out)
        #expect(file.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatAppleLossless)
        let seconds = Double(file.length) / file.processingFormat.sampleRate
        #expect(abs(seconds - 1) < 0.05, "\(seconds) s")
        let samples = try Self.samples(of: file)
        let rate = Int(file.processingFormat.sampleRate)
        #expect(Self.peak(samples[0 ..< rate / 1000]) < 0.1) // the first millisecond fades in
        #expect(Self.peak(samples[rate / 10 ..< rate / 5]) > 0.6) // still loud (9.2…9.4 s)
        #expect(Self.peak(samples[rate * 7 / 10 ..< rate * 9 / 10]) < 0.02) // silent after 10 s
    }

    @Test func lossySourcesBecomeAAC() async throws {
        let folder = try TemporaryDirectory()
        let song = folder.url.appendingPathComponent("song.m4a")
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
        let out = folder.url.appendingPathComponent("cut.m4a")
        try await SegmentExporter.export(SegmentExportRequest(source: song, kind: .audio, range: 0.5 ... 1.5), to: out)
        let file = try AVAudioFile(forReading: out)
        #expect(file.fileFormat.streamDescription.pointee.mFormatID == kAudioFormatMPEG4AAC)
        #expect(abs(Double(file.length) / file.processingFormat.sampleRate - 1) < 0.1)
    }

    static func samples(of file: AVAudioFile) throws -> [Float] {
        let buffer = try #require(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)))
        try file.read(into: buffer)
        let channel = try #require(buffer.floatChannelData?[0])
        return Array(UnsafeBufferPointer(start: channel, count: Int(buffer.frameLength)))
    }

    static func peak(_ samples: ArraySlice<Float>) -> Float {
        samples.map(abs).max() ?? 0
    }

    @Test func savesTheVideoFrameNextToTheVideoWithoutReplacing() async throws {
        let folder = try TemporaryDirectory()
        let movie = folder.url.appendingPathComponent("Clip.mov")
        try await MediaFactory.mov(at: movie, width: 64, height: 48, frames: 30, fps: 30)
        #expect(VideoFrame.fileName(for: movie, at: 62.3456) == "Clip 01-02.346.png")
        #expect(VideoFrame.fileName(for: movie, at: 3723.5) == "Clip 1-02-03.500.png")
        let image = try await VideoFrame.image(of: movie, at: 0.5)
        #expect(image.width == 64 && image.height == 48)
        let first = try VideoFrame.save(image, nextTo: movie, at: 0.5)
        let second = try VideoFrame.save(image, nextTo: movie, at: 0.5)
        #expect(first.lastPathComponent == "Clip 00-00.500.png")
        #expect(second.lastPathComponent == "Clip 00-00.500 2.png")
    }
}
