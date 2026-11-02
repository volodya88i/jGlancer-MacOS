import Foundation
import JGTestSupport
import Testing
@testable import JGStems

/// The real model end to end (developer runs only: `JG_STEM_MODELS=<folder with htdemucs.mlmodelc> swift test`).
/// Splits a generated 20-second song and checks that the four stems add up to it and the song is untouched.
struct StemModelRunTests {
    private static let models = ProcessInfo.processInfo.environment["JG_STEM_MODELS"].map { URL(fileURLWithPath: $0) }

    @Test(.enabled(if: models != nil)) func theStemsAddUpToTheSong() throws {
        let folder = try TemporaryDirectory()
        let song = folder.url.appendingPathComponent("song.wav")
        let seconds = Double(ProcessInfo.processInfo.environment["JG_STEM_SECONDS"] ?? "20") ?? 20
        try MediaFactory.wav(at: song, seconds: seconds, amplitude: 0.3)
        let before = try Data(contentsOf: song)
        let model = StemModelInfo.four
        let job = StemJob(
            song: song, model: model, stems: StemModelInfo.shown(.four),
            folder: folder.url.appendingPathComponent("song split"), makesFolder: true
        )
        let began = Date()
        let files = try StemJobRunner.run(
            job, compiledModel: #require(Self.models).appendingPathComponent("htdemucs.mlmodelc"),
            progress: { _ in }, isCancelled: { false }
        )
        let total = Date().timeIntervalSince(began)
        print("split \(seconds) s in \(total) s")
        #expect(files.map(\.lastPathComponent) == ["song - Vocals.wav", "song - Drums.wav", "song - Bass.wav", "song - Other.wav"])
        #expect(try Data(contentsOf: song) == before)
        let (left, _) = try StemAudioDecoder.decode(song, sampleRate: 44100)
        var sum = [Float](repeating: 0, count: left.count)
        for file in files {
            let (stem, _) = try StemAudioDecoder.decode(file, sampleRate: 44100)
            #expect(stem.count == left.count)
            for pos in 0 ..< min(stem.count, sum.count) {
                sum[pos] += stem[pos]
            }
        }
        let signal = (left.map { $0 * $0 }.reduce(0, +) / Float(left.count)).squareRoot()
        let error = (zip(sum, left).map { ($0 - $1) * ($0 - $1) }.reduce(0, +) / Float(left.count)).squareRoot()
        print("sum of the stems against the song: \(20 * log10(signal / max(error, 1e-12))) dB")
        #expect(error < signal * 0.1)
    }
}
