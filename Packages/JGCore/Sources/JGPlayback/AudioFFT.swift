import Accelerate

/// Magnitudes of a Hann-windowed block (D-106), through Accelerate's DFT; one instance per task.
final class AudioFFT {
    let size: Int
    private let setup: vDSP_DFT_Setup
    private let window: [Float]
    private var inReal: [Float]
    private let inImaginary: [Float]
    private var outReal: [Float]
    private var outImaginary: [Float]

    /// `size` must be a power of two of at least 16.
    init?(size: Int) {
        guard let setup = vDSP_DFT_zop_CreateSetup(nil, vDSP_Length(size), .FORWARD) else { return nil }
        self.size = size
        self.setup = setup
        window = (0 ..< size).map { Float(0.5 - 0.5 * cos(2 * Double.pi * Double($0) / Double(size))) }
        inReal = [Float](repeating: 0, count: size)
        inImaginary = [Float](repeating: 0, count: size)
        outReal = [Float](repeating: 0, count: size)
        outImaginary = [Float](repeating: 0, count: size)
    }

    deinit {
        vDSP_DFT_DestroySetup(setup)
    }

    /// Writes the magnitudes of bins 0 … size/2 of the block at `start` into `output`, scaled so full scale is about 1.
    func magnitudes(_ samples: UnsafeBufferPointer<Float>, start: Int, into output: inout [Float]) {
        let block = UnsafeBufferPointer(rebasing: samples[start ..< start + size])
        vDSP.multiply(block, window, result: &inReal)
        vDSP_DFT_Execute(setup, inReal, inImaginary, &outReal, &outImaginary)
        let scale = 4 / Float(size)
        for bin in 0 ... size / 2 {
            output[bin] = (outReal[bin] * outReal[bin] + outImaginary[bin] * outImaginary[bin]).squareRoot() * scale
        }
    }
}
