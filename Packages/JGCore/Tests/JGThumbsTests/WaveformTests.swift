import Foundation
import JGTestSupport
import Testing
@testable import JGThumbs

struct WaveformBucketingTests {
    @Test func spreadsSamplesEvenlyAndKeepsExtremes() {
        var bucketer = WaveformBucketer(expectedFrames: 100, bucketCount: 10)
        let samples = (0 ..< 100).map { Float($0 % 10) / 10 - 0.45 }
        samples.withUnsafeBufferPointer { bucketer.append($0) }
        let waveform = bucketer.waveform(complete: true)
        #expect(waveform.count == 10)
        #expect(waveform.filled == 10)
        for index in 0 ..< 10 {
            #expect(abs(waveform.low(at: index) + 0.45) < 0.01)
            #expect(abs(waveform.high(at: index) - 0.45) < 0.01)
        }
    }

    @Test func extraSamplesLandInTheLastBucket() {
        var bucketer = WaveformBucketer(expectedFrames: 10, bucketCount: 5)
        let samples: [Float] = Array(repeating: 0, count: 10) + [0.9]
        samples.withUnsafeBufferPointer { bucketer.append($0) }
        let waveform = bucketer.waveform(complete: true)
        #expect(waveform.high(at: 4) > 0.89)
        #expect(waveform.high(at: 3) == 0)
    }

    @Test func reportsOnlyFinishedBucketsWhilePartial() {
        var bucketer = WaveformBucketer(expectedFrames: 100, bucketCount: 10)
        let samples = [Float](repeating: 0.5, count: 35)
        samples.withUnsafeBufferPointer { bucketer.append($0) }
        #expect(bucketer.filledBuckets(complete: false) == 3)
        #expect(bucketer.waveform(complete: false).isComplete == false)
    }

    @Test func quantizesSymmetricallyAndSurvivesStorage() {
        #expect(Waveform.quantize(0) == 128)
        #expect(Waveform.quantize(1) == 255)
        #expect(Waveform.quantize(-1) == 1)
        #expect(Waveform.quantize(7) == 255)
        let waveform = Waveform(lows: [1, 100], highs: [200, 255], filled: 2, isComplete: true)
        #expect(Waveform(data: waveform.data) == waveform)
        #expect(Waveform(data: Data([1, 2, 3])) == nil)
    }
}

struct WaveformServiceTests {
    @Test func decodesAToneAndCachesItOnDisk() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("tone.wav")
        // 20 s keeps ~78 samples (several periods of 440 Hz) in each bucket.
        try MediaFactory.wav(at: url, seconds: 20, amplitude: 0.8, loudSeconds: 10)
        let disk = try ThumbnailDiskCache.inMemory()
        let request = WaveformRequest(url: url, assetID: 7, modifiedAt: Date(timeIntervalSince1970: 1000))
        let waveform = try #require(await Self.last(WaveformService(disk: disk), request))
        #expect(waveform.isComplete)
        let half = Waveform.bucketCount / 2
        #expect(waveform.high(at: half / 2) > 0.7)
        #expect(waveform.low(at: half / 2) < -0.7)
        #expect(abs(waveform.high(at: half + half / 2)) < 0.01)
        #expect(try await disk.waveform(assetID: 7, modifiedAt: 1_000_000) == waveform)
        // A new service (empty memory) finds it on disk, even after the file is gone.
        try FileManager.default.removeItem(at: url)
        #expect(await Self.last(WaveformService(disk: disk), request) == waveform)
    }

    @Test func readsFinePeaksOfARange() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("tone.wav")
        try MediaFactory.wav(at: url, seconds: 20, amplitude: 0.8, loudSeconds: 10)
        // 9…11 s: loud, then silent from 10 s.
        let detail = try #require(await WaveformService(disk: nil).detail(for: url, range: 9 ... 11, bucketCount: 400))
        #expect(detail.range == 9 ... 11)
        #expect(detail.highs.count == 400)
        #expect(detail.highs[100] > 0.7 && detail.lows[100] < -0.7)
        #expect(abs(detail.highs[300]) < 0.01)
    }

    @Test func publishesPartialResultsForLongFiles() async throws {
        let directory = try TemporaryDirectory()
        let url = directory.url.appendingPathComponent("long.wav")
        try MediaFactory.wav(at: url, seconds: 60, amplitude: 0.5)
        var results: [Waveform] = []
        for await waveform in WaveformService(disk: nil).waveform(for: WaveformRequest(url: url, assetID: nil, modifiedAt: nil)) {
            results.append(waveform)
        }
        #expect(results.count > 2)
        #expect(results.last?.isComplete == true)
        #expect(results.dropLast().allSatisfy { !$0.isComplete })
        #expect(results.map(\.filled) == results.map(\.filled).sorted())
    }

    @Test func finishesEmptyForFilesWithoutAudio() async throws {
        let directory = try TemporaryDirectory()
        let movie = directory.url.appendingPathComponent("silent.mov")
        try await MediaFactory.mov(at: movie, width: 32, height: 32, frames: 5, fps: 10)
        let fake = try directory.write("fake.mp3", "not audio")
        let service = WaveformService(disk: nil)
        #expect(await Self.last(service, WaveformRequest(url: movie, assetID: nil, modifiedAt: nil)) == nil)
        #expect(await Self.last(service, WaveformRequest(url: fake, assetID: nil, modifiedAt: nil)) == nil)
    }

    static func last(_ service: WaveformService, _ request: WaveformRequest) async -> Waveform? {
        var last: Waveform?
        for await waveform in service.waveform(for: request) {
            last = waveform
        }
        return last
    }
}
