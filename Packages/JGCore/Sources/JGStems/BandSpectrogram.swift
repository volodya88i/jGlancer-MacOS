import Accelerate

/// The spectrogram Mel-Band RoFormer works on (D-131), computed here because the Core ML model holds only the network:
/// PyTorch's `stft` / `istft` with a 2048-point periodic Hann window, hop 441, not normalized, centred with reflection,
/// all 1025 bins. Layout: frame after frame, the bins of each frame together. One instance per thread (it keeps its
/// work buffers).
public final class BandSpectrogram {
    public static let size = 2048
    public static let hop = 441
    public static let bins = size / 2 + 1

    private let forwardTransform: vDSP.DiscreteFourierTransform<Float>
    private let inverseTransform: vDSP.DiscreteFourierTransform<Float>
    private let window: [Float]
    private var inReal = [Float](repeating: 0, count: size)
    private var inImaginary = [Float](repeating: 0, count: size)
    private var outReal = [Float](repeating: 0, count: size)
    private var outImaginary = [Float](repeating: 0, count: size)

    public init() throws {
        forwardTransform = try vDSP.DiscreteFourierTransform(
            count: Self.size, direction: .forward, transformType: .complexComplex, ofType: Float.self
        )
        inverseTransform = try vDSP.DiscreteFourierTransform(
            count: Self.size, direction: .inverse, transformType: .complexComplex, ofType: Float.self
        )
        window = (0 ..< Self.size).map { Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(Self.size))) }
    }

    /// Frames of a piece of `length` samples.
    public static func frames(_ length: Int) -> Int {
        length / hop + 1
    }

    /// The spectrum of one channel of `length` samples (more than 1024) into `real` / `imaginary`
    /// (`frames(length)` × `bins`).
    public func forward(
        _ signal: UnsafeBufferPointer<Float>, real: UnsafeMutableBufferPointer<Float>,
        imaginary: UnsafeMutableBufferPointer<Float>
    ) {
        let length = signal.count
        for frame in 0 ..< Self.frames(length) {
            // torch.stft centres frame t on sample t × hop, reflecting n_fft/2 samples past each end.
            let start = frame * Self.hop - Self.size / 2
            for tap in 0 ..< Self.size {
                inReal[tap] = signal[Spectrogram.reflect(start + tap, length)] * window[tap]
                inImaginary[tap] = 0
            }
            forwardTransform.transform(
                inputReal: inReal, inputImaginary: inImaginary, outputReal: &outReal, outputImaginary: &outImaginary
            )
            let base = frame * Self.bins
            for bin in 0 ..< Self.bins {
                real[base + bin] = outReal[bin]
                imaginary[base + bin] = outImaginary[bin]
            }
        }
    }

    /// The `length` samples of one channel from its spectrum (`frames(length)` × `bins`), as torch.istft: the inverse
    /// of each frame windowed and overlapped, divided by the overlapping windows' squares.
    public func inverse(
        real: UnsafeBufferPointer<Float>, imaginary: UnsafeBufferPointer<Float>, into output: UnsafeMutableBufferPointer<Float>
    ) {
        let length = output.count
        let frames = Self.frames(length)
        let total = Self.size + Self.hop * (frames - 1)
        var signal = [Float](repeating: 0, count: total)
        var envelope = [Float](repeating: 0, count: total)
        // The inverse DFT here does not divide by n_fft.
        let scaledWindow = window.map { $0 / Float(Self.size) }
        let squares = window.map { $0 * $0 }
        let size = Self.size
        for frame in 0 ..< frames {
            loadFrame(real, imaginary, frame: frame)
            inverseTransform.transform(
                inputReal: inReal, inputImaginary: inImaginary, outputReal: &outReal, outputImaginary: &outImaginary
            )
            let start = frame * Self.hop
            signal.withUnsafeMutableBufferPointer { buffer in
                guard let target = buffer.baseAddress else { return }
                vDSP_vma(outReal, 1, scaledWindow, 1, target + start, 1, target + start, 1, vDSP_Length(size))
            }
            envelope.withUnsafeMutableBufferPointer { buffer in
                guard let target = buffer.baseAddress else { return }
                vDSP_vadd(squares, 1, target + start, 1, target + start, 1, vDSP_Length(size))
            }
        }
        let first = Self.size / 2
        for index in 0 ..< length {
            let weight = envelope[first + index]
            output[index] = weight > 1e-11 ? signal[first + index] / weight : 0
        }
    }

    /// One frame as a full complex spectrum in the work buffers: the upper half mirrors the lower (a real signal), and
    /// the first and last bins are real, as irfft takes them.
    private func loadFrame(_ real: UnsafeBufferPointer<Float>, _ imaginary: UnsafeBufferPointer<Float>, frame: Int) {
        let base = frame * Self.bins
        let last = Self.bins - 1
        for bin in 0 ... last {
            inReal[bin] = real[base + bin]
            inImaginary[bin] = imaginary[base + bin]
        }
        inImaginary[0] = 0
        inImaginary[last] = 0
        for bin in 1 ..< last {
            inReal[Self.size - bin] = inReal[bin]
            inImaginary[Self.size - bin] = -inImaginary[bin]
        }
    }
}
