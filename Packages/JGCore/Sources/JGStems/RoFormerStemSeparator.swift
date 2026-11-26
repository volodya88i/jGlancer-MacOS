import CoreML
import Foundation

/// Mel-Band RoFormer (D-131) as a `StemSeparator` with one source, the vocals: the Swift spectrogram, each mel band's
/// bins gathered for the Core ML network (on the GPU at full precision, as Demucs, D-97), its complex masks averaged
/// where bands overlap and applied, then the Swift inverse. Pieces of 8 s overlapping by half, the audio as it is (no
/// normalizing), as the model's own inference. One per split: it holds about 1 GB.
public final class RoFormerStemSeparator: StemSeparator {
    public let info: StemModelInfo
    private let model: MLModel
    private let spectrogram: BandSpectrogram
    private let frames: Int
    /// Per channel, the piece's spectrum and the vocals mask (frames × bins).
    private var real: [[Float]]
    private var imaginary: [[Float]]
    private var maskReal: [[Float]]
    private var maskImaginary: [[Float]]

    public var sources: Int {
        1
    }

    public var segmentFrames: Int {
        info.segmentFrames
    }

    public var overlap: Double {
        0.5
    }

    public var normalizes: Bool {
        false
    }

    /// Opens a compiled model (`.mlmodelc`).
    public init(compiledModel url: URL, info: StemModelInfo, computeUnits: MLComputeUnits = .cpuAndGPU) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        model = try MLModel(contentsOf: url, configuration: configuration)
        self.info = info
        spectrogram = try BandSpectrogram()
        frames = BandSpectrogram.frames(info.segmentFrames)
        let empty = [Float](repeating: 0, count: frames * BandSpectrogram.bins)
        real = [empty, empty]
        imaginary = real
        maskReal = real
        maskImaginary = real
    }

    public func separate(_ input: UnsafeBufferPointer<Float>, into output: UnsafeMutableBufferPointer<Float>) throws {
        let length = segmentFrames
        for channel in 0 ..< 2 {
            let signal = UnsafeBufferPointer(rebasing: input[channel * length ..< (channel + 1) * length])
            real[channel].withUnsafeMutableBufferPointer { realBuffer in
                imaginary[channel].withUnsafeMutableBufferPointer { spectrogram.forward(signal, real: realBuffer, imaginary: $0) }
            }
        }
        let bands = try MLMultiArray(shape: [1, NSNumber(value: frames), NSNumber(value: MelBands.features)], dataType: .float32)
        bands.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in gather(into: buffer) }
        let result = try model.prediction(from: MLDictionaryFeatureProvider(dictionary: ["bands": bands]))
        guard let masks = result.featureValue(for: "masks")?.multiArrayValue else {
            throw StemModelError.badOutput("missing masks")
        }
        let values = try CoreMLStemSeparator.contiguous(masks, count: frames * MelBands.features)
        values.withUnsafeBufferPointer(average)
        for channel in 0 ..< 2 {
            apply(channel)
            let target = UnsafeMutableBufferPointer(rebasing: output[channel * length ..< (channel + 1) * length])
            real[channel].withUnsafeBufferPointer { realBuffer in
                imaginary[channel].withUnsafeBufferPointer { spectrogram.inverse(real: realBuffer, imaginary: $0, into: target) }
            }
        }
    }

    /// The network's input: per frame, each band's bins, left then right, real then imaginary.
    private func gather(into buffer: UnsafeMutableBufferPointer<Float>) {
        let bins = BandSpectrogram.bins
        var index = 0
        for frame in 0 ..< frames {
            let base = frame * bins
            for bin in MelBands.bins {
                for channel in 0 ..< 2 {
                    buffer[index] = real[channel][base + bin]
                    buffer[index + 1] = imaginary[channel][base + bin]
                    index += 2
                }
            }
        }
    }

    /// The masks of all bands added up per bin and divided by the number of bands the bin is in.
    private func average(_ values: UnsafeBufferPointer<Float>) {
        let bins = BandSpectrogram.bins
        for channel in 0 ..< 2 {
            maskReal[channel].withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
            maskImaginary[channel].withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
        }
        var index = 0
        for frame in 0 ..< frames {
            let base = frame * bins
            for bin in MelBands.bins {
                for channel in 0 ..< 2 {
                    maskReal[channel][base + bin] += values[index]
                    maskImaginary[channel][base + bin] += values[index + 1]
                    index += 2
                }
            }
        }
        for channel in 0 ..< 2 {
            for frame in 0 ..< frames {
                for bin in 0 ..< bins {
                    let count = MelBands.coverage[bin]
                    maskReal[channel][frame * bins + bin] /= count
                    maskImaginary[channel][frame * bins + bin] /= count
                }
            }
        }
    }

    /// The spectrum times its mask, as complex numbers.
    private func apply(_ channel: Int) {
        for index in 0 ..< frames * BandSpectrogram.bins {
            let (realPart, imaginaryPart) = (real[channel][index], imaginary[channel][index])
            let (maskRealPart, maskImaginaryPart) = (maskReal[channel][index], maskImaginary[channel][index])
            real[channel][index] = realPart * maskRealPart - imaginaryPart * maskImaginaryPart
            imaginary[channel][index] = realPart * maskImaginaryPart + imaginaryPart * maskRealPart
        }
    }
}
