import Foundation
import JGTestSupport
import Testing
@testable import JGStems

/// A network like RoFormer's for the splitter (half overlap, the audio as it is) that gives each piece back and keeps
/// the first one it got.
private final class Passthrough: StemSeparator {
    let segmentFrames: Int
    var firstInput: [Float]?

    var sources: Int {
        1
    }

    var overlap: Double {
        0.5
    }

    var normalizes: Bool {
        false
    }

    init(segment: Int) {
        segmentFrames = segment
    }

    func separate(_ input: UnsafeBufferPointer<Float>, into output: UnsafeMutableBufferPointer<Float>) {
        if firstInput == nil {
            firstInput = Array(input)
        }
        _ = output.update(fromContentsOf: input)
    }
}

private final class Gather: StemSink {
    var left: [Float] = []
    var right: [Float] = []

    func write(left: ArraySlice<Float>, right: ArraySlice<Float>) {
        self.left += left
        self.right += right
    }
}

struct RoFormerTests {
    private static let reference = ProcessInfo.processInfo.environment["JG_ROFORMER_REFERENCE"].map { URL(fileURLWithPath: $0) }
    private static let models = ProcessInfo.processInfo.environment["JG_STEM_MODELS"].map { URL(fileURLWithPath: $0) }

    @Test func theBandSpectrogramIsPyTorchsAndInvertsBack() throws {
        let length = 44100
        let signal = (0 ..< length).map { pos -> Float in
            let time = Double(pos) / 44100
            return Float(
                0.5 * sin(2 * .pi * 440 * time) + 0.25 * sin(2 * .pi * 3000 * time + 1) + 0.1 * cos(2 * .pi * 12345 * time)
            )
        }
        let frames = BandSpectrogram.frames(length)
        #expect(frames == 101)
        let transform = try BandSpectrogram()
        var real = [Float](repeating: 0, count: frames * BandSpectrogram.bins)
        var imaginary = real
        signal.withUnsafeBufferPointer { input in
            real.withUnsafeMutableBufferPointer { realBuffer in
                imaginary.withUnsafeMutableBufferPointer { transform.forward(input, real: realBuffer, imaginary: $0) }
            }
        }
        // Frame, bin, real, imaginary: torch.stft(x, 2048, 441, 2048, torch.hann_window(2048)) of this signal.
        let expected: [[Double]] = [
            [0, 0, 16.592, 0], [0, 20, 101.143, 0], [5, 20, 0, -226.435], [50, 139, -100.792, 64.7179],
            [100, 573, -4.12125, 22.1795], [37, 1024, 0, 0], [64, 300, 0, 0], [100, 20, -115.37, -6.73499],
        ]
        for entry in expected {
            let index = Int(entry[0]) * BandSpectrogram.bins + Int(entry[1])
            #expect(abs(Double(real[index]) - entry[2]) < 2e-3)
            #expect(abs(Double(imaginary[index]) - entry[3]) < 2e-3)
        }
        var back = [Float](repeating: 0, count: length)
        real.withUnsafeBufferPointer { realBuffer in
            imaginary.withUnsafeBufferPointer { imaginaryBuffer in
                back.withUnsafeMutableBufferPointer { transform.inverse(real: realBuffer, imaginary: imaginaryBuffer, into: $0) }
            }
        }
        let worst = zip(back, signal).map { abs($0 - $1) }.max() ?? 1
        #expect(worst < 1e-4)
    }

    @Test func theMelBandsHaveTheCheckpointsSizes() {
        // The input width of each band's first layer in MelBandRoformer.ckpt: 4 × its bins.
        let widths = [
            28, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 24, 28, 28, 28, 36, 36, 36, 40, 40, 44, 52, 52, 52, 60,
            64, 68, 76, 80, 80, 88, 96, 104, 112, 116, 124, 132, 144, 156, 164, 176, 188, 200, 216, 228, 244, 264, 284, 304,
            320, 344, 372, 396, 420, 452, 488, 520,
        ]
        #expect(MelBands.bands.map { 4 * $0.count } == widths)
        #expect(MelBands.bins.count == 1979)
        #expect(MelBands.features == 7916)
        #expect(MelBands.bands.first?.start == 0)
        #expect(MelBands.bands.last.map { $0.start + $0.count } == BandSpectrogram.bins)
        #expect(MelBands.coverage.allSatisfy { $0 == 1 || $0 == 2 })
        for (previous, band) in zip(MelBands.bands, MelBands.bands.dropFirst()) {
            #expect(band.start > previous.start && band.start <= previous.start + previous.count)
        }
    }

    @Test func highQualityTwoStemsRunRoFormer() throws {
        let standard = StemChoice(mode: .two)
        #expect(standard.network == .four)
        let high = standard.with(highQuality: true)
        #expect(high.network == .vocals)
        #expect(high.with(mode: .four).network == .four)
        #expect(high.with(mode: .four).with(mode: .two).network == .vocals)
        #expect(StemModelInfo.model(for: .vocals) == .roformer)
        #expect(StemModelInfo.model(for: .vocals, full: false) == .roformerCompact)
        #expect(StemModelInfo.roformer.part(of: .vocals) == .source(0))
        #expect(StemModelInfo.roformer.part(of: .instrumental) == .songWithout(0))
        #expect(StemModelInfo.roformer.part(of: .drums) == nil)
        #expect(StemModelStore.source(for: .roformer).url.absoluteString.hasSuffix("/models-mac-2/mel_band_roformer-coreml.zip"))
        #expect(StemModelStore.source(for: .fourCompact).url.absoluteString.hasSuffix("/models-mac-1/htdemucs-compact-coreml.zip"))
        // A choice saved before High Quality existed reads as Standard; a High Quality one comes back as it was.
        let saved = Data(#"{"mode":"two","ticked":["Vocals","Instrumental"]}"#.utf8)
        #expect(try JSONDecoder().decode(StemChoice.self, from: saved) == standard)
        #expect(try JSONDecoder().decode(StemChoice.self, from: JSONEncoder().encode(high)) == high)
    }

    @Test func piecesOverlappingByHalfJoinBackToTheSongAsItIs() throws {
        let frames = 5000
        let left = (0 ..< frames).map { 0.5 * sin(Float($0) * 0.031) + 0.1 }
        let right = (0 ..< frames).map { 0.3 * cos(Float($0) * 0.0071) }
        let separator = Passthrough(segment: 1000)
        let vocals = Gather()
        var pieces = 0
        try StemSplitter.split(
            left: left, right: right, separator: separator, outputs: [StemOutput(.source(0), to: vocals)]
        ) { _ in pieces += 1 }
        #expect(pieces == StemSplitter.plan(frames: frames, segment: 1000, overlap: 0.5).count)
        #expect(pieces == 10)
        // Not normalized: the network gets the samples themselves.
        #expect(separator.firstInput.map { Array($0[0 ..< 1000]) } == Array(left[0 ..< 1000]))
        for pos in 0 ..< frames {
            #expect(abs(vocals.left[pos] - left[pos]) < 1e-5)
            #expect(abs(vocals.right[pos] - right[pos]) < 1e-5)
        }
    }

    /// The real model end to end (developer runs only): `JG_STEM_MODELS=<folder with mel_band_roformer.mlmodelc>
    /// JG_ROFORMER_REFERENCE=<folder from convert_roformer_coreml.py … reference> swift test -c release`.
    @Test(.enabled(if: models != nil && reference != nil)) func theVocalsAreThoseOfPyTorch() throws {
        let folder = try #require(Self.reference)
        let mix = try Self.floats(folder.appendingPathComponent("reference.f32"))
        let expected = try Self.floats(folder.appendingPathComponent("reference-vocals.f32"))
        let frames = mix.count / 2
        let separator = try RoFormerStemSeparator(
            compiledModel: #require(Self.models).appendingPathComponent("mel_band_roformer.mlmodelc"), info: .roformer
        )
        let vocals = Gather()
        let began = Date()
        try StemSplitter.split(
            left: Array(mix[0 ..< frames]), right: Array(mix[frames...]), separator: separator,
            outputs: [StemOutput(.source(0), to: vocals)]
        )
        let seconds = Date().timeIntervalSince(began)
        let got = vocals.left + vocals.right
        #expect(got.count == expected.count)
        var signal = 0.0
        var error = 0.0
        for (value, target) in zip(got, expected) {
            signal += Double(target) * Double(target)
            error += Double(value - target) * Double(value - target)
        }
        let decibels = 10 * log10(signal / max(error, 1e-20))
        print("RoFormer: \(Double(frames) / 44100) s split in \(seconds) s, vocals \(decibels) dB against PyTorch")
        #expect(decibels > 60)
    }

    private static func floats(_ url: URL) throws -> [Float] {
        let data = try Data(contentsOf: url)
        return data.withUnsafeBytes { Array($0.bindMemory(to: Float.self)) }
    }
}
