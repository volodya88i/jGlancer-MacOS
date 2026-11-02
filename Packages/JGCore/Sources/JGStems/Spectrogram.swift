import Accelerate
import Foundation

/// The spectrogram HTDemucs works on (D-97), computed here because the model holds only the network (as on Windows,
/// W-85): PyTorch's `stft` / `istft` with a 4096-point periodic Hann window, hop 1024, normalized, centred with
/// reflection, plus Demucs' own padding (`HTDemucs._spec` / `_ispec`), so the network sees exactly what it was trained
/// on. Layout: channels (left real, left imag, right real, right imag) × 2048 bins × frames, the highest bin dropped. One
/// instance per thread (it keeps its work buffers).
public final class Spectrogram {
    public static let size = 4096
    public static let hop = size / 4
    public static let bins = size / 2
    /// Demucs pads the signal by 1.5 hops each side before the STFT.
    static let pad = hop / 2 * 3

    private let forward: vDSP.DiscreteFourierTransform<Float>
    private let inverse: vDSP.DiscreteFourierTransform<Float>
    private let window: [Float]
    private var inReal = [Float](repeating: 0, count: size)
    private var inImaginary = [Float](repeating: 0, count: size)
    private var outReal = [Float](repeating: 0, count: size)
    private var outImaginary = [Float](repeating: 0, count: size)

    public init() throws {
        forward = try vDSP.DiscreteFourierTransform(
            count: Self.size, direction: .forward, transformType: .complexComplex, ofType: Float.self
        )
        inverse = try vDSP.DiscreteFourierTransform(
            count: Self.size, direction: .inverse, transformType: .complexComplex, ofType: Float.self
        )
        window = (0 ..< Self.size).map { Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(Self.size))) }
    }

    /// Frames of a piece of `length` samples.
    public static func frames(_ length: Int) -> Int {
        (length + hop - 1) / hop
    }

    /// The spectrogram of a stereo piece (planar: `length` left samples, then right) into `spec`
    /// (4 × `bins` × `frames(length)`).
    public func forward(_ mix: UnsafeBufferPointer<Float>, length: Int, into spec: UnsafeMutableBufferPointer<Float>) {
        let frames = Self.frames(length)
        let padded = length + 2 * Self.pad + frames * Self.hop - length
        let scale = 1 / Float(Self.size).squareRoot()
        for channel in 0 ..< 2 {
            let signal = channel * length
            let realBase = channel * 2 * Self.bins * frames
            let imaginaryBase = realBase + Self.bins * frames
            for frame in 0 ..< frames {
                // torch.stft centres frames by reflecting n_fft/2 samples; Demucs keeps frames 2 … 2 + frames.
                let start = (frame + 2) * Self.hop - Self.size / 2
                for tap in 0 ..< Self.size {
                    let position = Self.reflect(start + tap, padded)
                    inReal[tap] = mix[signal + Self.reflect(position - Self.pad, length)] * window[tap]
                    inImaginary[tap] = 0
                }
                forward.transform(inputReal: inReal, inputImaginary: inImaginary, outputReal: &outReal, outputImaginary: &outImaginary)
                for bin in 0 ..< Self.bins {
                    spec[realBase + bin * frames + frame] = outReal[bin] * scale
                    spec[imaginaryBase + bin * frames + frame] = outImaginary[bin] * scale
                }
            }
        }
    }

    /// Inverts the sources' spectrograms (`sources` × 4 × `bins` × frames) and adds the waveforms to `output`
    /// (sources × 2 × `length`).
    public func inverseAdd(
        _ spec: UnsafeBufferPointer<Float>, sources: Int, length: Int, to output: UnsafeMutableBufferPointer<Float>
    ) {
        let frames = Self.frames(length)
        // Demucs adds two empty frames each side; torch.istft then drops n_fft/2 samples and Demucs the padding.
        let allFrames = frames + 4
        let total = Self.size + Self.hop * (allFrames - 1)
        var envelope = [Float](repeating: 0, count: total)
        for frame in 0 ..< allFrames {
            for tap in 0 ..< Self.size {
                envelope[frame * Self.hop + tap] += window[tap] * window[tap]
            }
        }
        var signal = [Float](repeating: 0, count: total)
        // istft(normalized) multiplies by √n_fft; the inverse DFT here does not divide by n_fft.
        let scale = Float(Self.size).squareRoot() / Float(Self.size)
        let scaledWindow = window.map { $0 * scale }
        let first = Self.size / 2 + Self.pad
        let size = Self.size
        let bins = Self.bins
        guard let base = spec.baseAddress, let out = output.baseAddress else { return }
        for source in 0 ..< sources {
            for channel in 0 ..< 2 {
                signal.withUnsafeMutableBufferPointer { $0.update(repeating: 0) }
                let realBase = (source * 4 + channel * 2) * bins * frames
                let imaginaryBase = realBase + bins * frames
                for frame in 0 ..< frames {
                    loadFrame(base + realBase + frame, base + imaginaryBase + frame, stride: frames)
                    inverse.transform(inputReal: inReal, inputImaginary: inImaginary, outputReal: &outReal, outputImaginary: &outImaginary)
                    let start = (frame + 2) * Self.hop
                    signal.withUnsafeMutableBufferPointer { buffer in
                        guard let target = buffer.baseAddress else { return }
                        vDSP_vma(outReal, 1, scaledWindow, 1, target + start, 1, target + start, 1, vDSP_Length(size))
                    }
                }
                let target = out + (source * 2 + channel) * length
                for index in 0 ..< length {
                    let weight = envelope[first + index]
                    target[index] += weight > 1e-11 ? signal[first + index] / weight : 0
                }
            }
        }
    }

    /// One frame of a source's spectrogram (a stride of `stride` through the bins) as a full complex spectrum in the
    /// work buffers: the dropped top bin is zero, the rest mirror (a real signal), DC and top are real.
    private func loadFrame(_ realSource: UnsafePointer<Float>, _ imaginarySource: UnsafePointer<Float>, stride: Int) {
        let bins = Self.bins
        let count = vDSP_Length(bins - 1)
        inReal.withUnsafeMutableBufferPointer { realBuffer in
            inImaginary.withUnsafeMutableBufferPointer { imaginaryBuffer in
                guard let real = realBuffer.baseAddress, let imag = imaginaryBuffer.baseAddress else { return }
                var one: Float = 1
                vDSP_vsmul(realSource, stride, &one, real, 1, vDSP_Length(bins))
                vDSP_vsmul(imaginarySource, stride, &one, imag, 1, vDSP_Length(bins))
                imag[0] = 0
                real[bins] = 0
                imag[bins] = 0
                // The upper half is the lower one reversed (imaginary parts negated).
                vDSP_vrvrs(real + 1, 1, count)
                (real + bins + 1).update(from: real + 1, count: bins - 1)
                vDSP_vrvrs(real + 1, 1, count)
                vDSP_vrvrs(imag + 1, 1, count)
                (imag + bins + 1).update(from: imag + 1, count: bins - 1)
                vDSP_vneg(imag + bins + 1, 1, imag + bins + 1, 1, count)
                vDSP_vrvrs(imag + 1, 1, count)
            }
        }
    }

    /// Reflection padding as PyTorch's: -1 → 1, length → length - 2.
    static func reflect(_ index: Int, _ length: Int) -> Int {
        guard length > 1 else { return 0 }
        let period = 2 * (length - 1)
        var wrapped = index % period
        if wrapped < 0 {
            wrapped += period
        }
        return wrapped < length ? wrapped : period - wrapped
    }
}
