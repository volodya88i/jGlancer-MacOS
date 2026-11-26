import Foundation
import JGTestSupport
import Testing
@testable import JGStems

/// Every source is the piece itself: joining the pieces must give the song back.
private final class Identity: StemSeparator {
    let sources: Int
    let segmentFrames: Int
    var runs = 0

    init(sources: Int, segment: Int) {
        self.sources = sources
        segmentFrames = segment
    }

    func separate(_ input: UnsafeBufferPointer<Float>, into output: UnsafeMutableBufferPointer<Float>) {
        runs += 1
        for source in 0 ..< sources {
            for pos in input.indices {
                output[source * input.count + pos] = input[pos]
            }
        }
    }
}

/// Source n is the piece times `shares[n]`.
private final class Scaled: StemSeparator {
    let shares: [Float]
    let segmentFrames: Int

    var sources: Int {
        shares.count
    }

    init(_ shares: [Float], segment: Int) {
        self.shares = shares
        segmentFrames = segment
    }

    func separate(_ input: UnsafeBufferPointer<Float>, into output: UnsafeMutableBufferPointer<Float>) {
        for (source, share) in shares.enumerated() {
            for pos in input.indices {
                output[source * input.count + pos] = input[pos] * share
            }
        }
    }
}

private final class Collect: StemSink {
    var left: [Float] = []
    var right: [Float] = []

    func write(left: ArraySlice<Float>, right: ArraySlice<Float>) {
        self.left += left
        self.right += right
    }
}

private func song(_ frames: Int) -> ([Float], [Float]) {
    let left = (0 ..< frames).map { 0.5 * sin(Float($0) * 0.031) + 0.1 }
    let right = (0 ..< frames).map { 0.3 * cos(Float($0) * 0.0071) - 0.2 * sin(Float($0) * 0.17) }
    return (left, right)
}

struct StemSplitterTests {
    @Test func piecesOverlapByAQuarterAndCoverTheSong() {
        #expect(StemSplitter.plan(frames: 2500, segment: 1000) == [
            StemSegment(offset: 0, length: 1000), StemSegment(offset: 750, length: 1000),
            StemSegment(offset: 1500, length: 1000), StemSegment(offset: 2250, length: 250),
        ])
        #expect(StemSplitter.plan(frames: 300, segment: 1000) == [StemSegment(offset: 0, length: 300)])
        #expect(StemSplitter.weights(8) == [0.25, 0.5, 0.75, 1, 1, 0.75, 0.5, 0.25])
    }

    @Test(arguments: [(4321, 1000), (300, 1000), (1000, 1000)])
    func joiningThePiecesOfAnIdentityGivesTheSongBack(frames: Int, segment: Int) throws {
        let (left, right) = song(frames)
        let separator = Identity(sources: 4, segment: segment)
        let vocals = Collect()
        let bass = Collect()
        var progress: [Double] = []
        try StemSplitter.split(
            left: left, right: right, separator: separator,
            outputs: [StemOutput(.source(3), to: vocals), StemOutput(.source(1), to: bass)]
        ) { progress.append($0) }
        #expect(vocals.left.count == frames)
        #expect(bass.right.count == frames)
        for pos in 0 ..< frames {
            #expect(abs(vocals.left[pos] - left[pos]) < 1e-5)
            #expect(abs(vocals.right[pos] - right[pos]) < 1e-5)
            #expect(abs(bass.right[pos] - right[pos]) < 1e-5)
        }
        #expect(progress.last == 1)
        #expect(progress.count == separator.runs)
    }

    @Test func stoppingEndsBetweenPieces() {
        let (left, right) = song(5000)
        let separator = Identity(sources: 4, segment: 1000)
        var stop = false
        #expect(throws: StemSplitCancelled.self) {
            try StemSplitter.split(
                left: left, right: right, separator: separator, outputs: [StemOutput(.source(0), to: Collect())],
                progress: { _ in stop = true },
                isCancelled: { stop }
            )
        }
        #expect(separator.runs == 1)
    }

    @Test func theSpectrogramIsPyTorchs() throws {
        // Values from the Windows tests (HTDemucs._spec + _magnitude of this signal in PyTorch).
        let length = 343_980
        var mix = [Float](repeating: 0, count: 2 * length)
        for pos in 0 ..< length {
            let time = Double(pos) / 44100
            mix[pos] = Float(0.5 * sin(2 * .pi * 440 * time) + 0.25 * sin(2 * .pi * 3000 * time + 1))
            mix[length + pos] = Float(0.4 * sin(2 * .pi * 97 * time) + 0.1 * cos(2 * .pi * 12345 * time))
        }
        let frames = Spectrogram.frames(length)
        #expect(frames == 336)
        let transform = try Spectrogram()
        var spec = [Float](repeating: 0, count: 4 * Spectrogram.bins * frames)
        mix.withUnsafeBufferPointer { input in
            spec.withUnsafeMutableBufferPointer { transform.forward(input, length: length, into: $0) }
        }
        // Channel, bin, frame, value.
        let expected: [[Double]] = [
            [0, 0, 0, 0.2209745], [0, 40, 0, 5.112086], [1, 40, 5, -1.70224], [2, 9, 100, -4.937966],
            [3, 9, 100, -4.070854], [0, 278, 335, -0.1851368], [1, 278, 200, -2.963294],
            [2, 1146, 17, -0.9236326], [3, 2047, 335, 0.0009935535], [2, 2, 1, 0.02341787],
        ]
        for entry in expected {
            let (channel, bin, frame) = (Int(entry[0]), Int(entry[1]), Int(entry[2]))
            #expect(abs(spec[(channel * Spectrogram.bins + bin) * frames + frame] - Float(entry[3])) < 2e-3)
        }
        // The inverse of the spectrogram is the piece again (one "source" that is the mix), except near its ends.
        var back = [Float](repeating: 0, count: 2 * length)
        spec.withUnsafeBufferPointer { input in
            back.withUnsafeMutableBufferPointer { transform.inverseAdd(input, sources: 1, length: length, to: $0) }
        }
        for channel in 0 ..< 2 {
            for pos in stride(from: Spectrogram.size, to: length - Spectrogram.size, by: 997) {
                #expect(abs(back[channel * length + pos] - mix[channel * length + pos]) < 1e-3)
            }
        }
    }
}

struct StemChoiceTests {
    @Test func foldersAndFilesAreNamedAfterTheSong() {
        let music = URL(fileURLWithPath: "/Music")
        let taken: Set = [music.appendingPathComponent("Lekarstvo split").path, music.appendingPathComponent("Lekarstvo split 2").path]
        let song = music.appendingPathComponent("Lekarstvo.mp3")
        #expect(StemNaming.defaultFolder(for: song, exists: { taken.contains($0.path) }).lastPathComponent == "Lekarstvo split 3")
        #expect(StemNaming.defaultFolder(for: music.appendingPathComponent("My.Song.flac")) { _ in
            false
        }.lastPathComponent == "My.Song split")
        #expect(StemNaming.fileName(for: song, stem: .vocals) == "Lekarstvo - Vocals.wav")
        #expect(StemNaming.safe("a/b:c") == "a_b_c")
        #expect(StemNaming.safe(".hidden ") == "hidden")
        #expect(StemNaming.safe("...") == "_")
    }

    @Test func atLeastOneStemStaysTickedAndModesShareTheirTicks() {
        var choice = StemChoice()
        #expect(choice.stems == [.vocals, .drums, .bass, .other])
        choice = choice.with(.drums, ticked: false).with(.bass, ticked: false).with(.other, ticked: false)
        #expect(choice.stems == [.vocals])
        #expect(choice.with(.vocals, ticked: false) == choice)
        let six = choice.with(mode: .six)
        #expect(six.stems == [.vocals, .guitar, .piano])
        let four = six.with(.vocals, ticked: false).with(mode: .four)
        #expect(four.stems == [.vocals, .drums, .bass, .other])
    }

    @Test func aStemIsA24BitWaveOfWhatWasWritten() throws {
        let folder = try TemporaryDirectory()
        let url = folder.url.appendingPathComponent("stem.wav")
        let writer = try WaveStemWriter(url: url, sampleRate: 44100)
        try writer.write(left: [0, 0.5, -1, 2], right: [1, -0.25, 0, -2])
        try writer.write(left: [0.125], right: [0])
        try writer.complete()
        let data = try Data(contentsOf: url)
        #expect(data.count == 44 + 5 * 6)
        #expect(String(bytes: data[0 ..< 4], encoding: .ascii) == "RIFF")
        func int(_ offset: Int, _ size: Int) -> Int {
            (0 ..< size).reduce(0) { $0 | Int(data[offset + $1]) << (8 * $1) }
        }
        #expect(int(24, 4) == 44100)
        #expect(int(34, 2) == 24)
        #expect(int(40, 4) == 30)
        func sample(_ index: Int) -> Float {
            let raw = Int32(truncatingIfNeeded: int(44 + index * 3, 3) << 8) >> 8
            return Float(raw) / 8_388_607
        }
        #expect(abs(sample(2) - 0.5) < 1e-6)
        #expect(abs(sample(4) + 1) < 1e-6)
        #expect(abs(sample(6) - 1) < 1e-6)
        #expect(abs(sample(7) + 1) < 1e-6)
        #expect(abs(sample(8) - 0.125) < 1e-6)
    }
}

struct StemTwoStemTests {
    @Test func theInstrumentalIsTheSongLessTheVocals() throws {
        let (left, right) = song(4321)
        let vocals = Collect()
        let instrumental = Collect()
        try StemSplitter.split(
            left: left, right: right, separator: Scaled([0.1, 0.2, 0.3, 0.4], segment: 1000),
            outputs: [StemOutput(.songWithout(3), to: instrumental), StemOutput(.source(3), to: vocals)]
        )
        let (mean, _) = StemSplitter.normalization(left, right, left.count)
        #expect(instrumental.left.count == left.count)
        for pos in left.indices {
            // The vocals: 0.4 of the normalized song, scaled back as Demucs does.
            #expect(abs(vocals.left[pos] - (0.4 * (left[pos] - mean) + mean)) < 1e-5)
            #expect(abs(instrumental.left[pos] + vocals.left[pos] - left[pos]) < 1e-5)
            #expect(abs(instrumental.right[pos] + vocals.right[pos] - right[pos]) < 1e-5)
        }
    }

    @Test func twoStemsAreTheVocalsAndTheInstrumentalOfTheFourStemNetwork() {
        #expect(StemModelInfo.shown(.two) == [.vocals, .instrumental])
        #expect(StemModelInfo.model(for: StemMode.two.network) == .four)
        #expect(StemModelInfo.model(for: StemMode.two.network, full: false) == .fourCompact)
        #expect(StemModelInfo.model(for: StemMode.six.network) == .six)
        #expect(StemModelInfo.four.part(of: .instrumental) == .songWithout(3))
        #expect(StemModelInfo.four.part(of: .vocals) == .source(3))
        #expect(StemModelInfo.four.part(of: .drums) == .source(0))
        #expect(StemModelInfo.four.part(of: .guitar) == nil)
        #expect(StemModelInfo.six.part(of: .piano) == .source(5))
        #expect(StemModelInfo.six.part(of: .instrumental) == .songWithout(3))
        #expect(StemNaming.fileName(for: URL(fileURLWithPath: "/Music/Lekarstvo.mp3"), stem: .instrumental)
            == "Lekarstvo - Instrumental.wav")
    }

    @Test func switchingToTwoStemsKeepsTheVocalsTickAndTicksTheInstrumental() throws {
        let two = StemChoice(mode: .two)
        #expect(two.stems == [.vocals, .instrumental])
        let onlyVocals = StemChoice().with(.drums, ticked: false).with(.bass, ticked: false).with(.other, ticked: false)
        #expect(onlyVocals.with(mode: .two).stems == [.vocals, .instrumental])
        let onlyInstrumental = two.with(.vocals, ticked: false)
        #expect(onlyInstrumental.stems == [.instrumental])
        #expect(onlyInstrumental.with(.instrumental, ticked: false) == onlyInstrumental)
        #expect(onlyInstrumental.with(mode: .four).stems == [.drums, .bass, .other])
        // A choice saved before 2 stems existed still reads, and a 2-stem one comes back as it was.
        let saved = Data(#"{"mode":"six","ticked":["Vocals","Guitar"]}"#.utf8)
        #expect(try JSONDecoder().decode(StemChoice.self, from: saved).stems == [.vocals, .guitar])
        let again = try JSONDecoder().decode(StemChoice.self, from: JSONEncoder().encode(onlyInstrumental))
        #expect(again == onlyInstrumental)
    }

    @Test func aTwoStemJobWritesTheVocalsAndTheInstrumental() throws {
        let folder = try TemporaryDirectory()
        let (left, right) = song(5000)
        let job = StemJob(
            song: folder.url.appendingPathComponent("Lekarstvo.mp3"), model: .four, stems: StemModelInfo.shown(.two),
            folder: folder.url.appendingPathComponent("Lekarstvo split"), makesFolder: true
        )
        let files = try StemJobRunner.write(
            job, song: (left, right), separator: Scaled([0.1, 0.2, 0.3, 0.4], segment: 1000),
            progress: { _ in }, isCancelled: { false }
        )
        #expect(files.map(\.lastPathComponent) == ["Lekarstvo - Vocals.wav", "Lekarstvo - Instrumental.wav"])
        let (vocalsLeft, vocalsRight) = try StemAudioDecoder.decode(files[0], sampleRate: 44100)
        let (restLeft, restRight) = try StemAudioDecoder.decode(files[1], sampleRate: 44100)
        #expect(vocalsLeft.count == left.count)
        #expect(restRight.count == right.count)
        for pos in 0 ..< min(left.count, vocalsLeft.count, restLeft.count, vocalsRight.count, restRight.count) {
            #expect(abs(vocalsLeft[pos] + restLeft[pos] - left[pos]) < 1e-5)
            #expect(abs(vocalsRight[pos] + restRight[pos] - right[pos]) < 1e-5)
        }
    }
}
