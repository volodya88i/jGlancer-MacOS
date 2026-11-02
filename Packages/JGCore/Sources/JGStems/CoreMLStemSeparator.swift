import CoreML
import Foundation

/// The model failed or gave something unexpected.
public enum StemModelError: Error, Equatable {
    case badOutput(String)
    case checksumMismatch
    case unpackFailed
}

/// Demucs (D-97) as a `StemSeparator`: the Swift spectrogram, the Core ML network on the GPU at full precision (the
/// Neural Engine computes in half precision, which garbles this network: measured below 0 dB against Demucs, against
/// 79-122 dB on the GPU), then the Swift inverse plus the time branch. One per split: it holds hundreds of MB.
public final class CoreMLStemSeparator: StemSeparator {
    public let info: StemModelInfo
    private let model: MLModel
    private let spectrogram: Spectrogram
    private let frames: Int
    private var spec: [Float]

    public var sources: Int {
        info.sources.count
    }

    public var segmentFrames: Int {
        info.segmentFrames
    }

    /// Opens a compiled model (`.mlmodelc`).
    public init(compiledModel url: URL, info: StemModelInfo, computeUnits: MLComputeUnits = .cpuAndGPU) throws {
        let configuration = MLModelConfiguration()
        configuration.computeUnits = computeUnits
        model = try MLModel(contentsOf: url, configuration: configuration)
        self.info = info
        spectrogram = try Spectrogram()
        frames = Spectrogram.frames(info.segmentFrames)
        spec = [Float](repeating: 0, count: 4 * Spectrogram.bins * frames)
    }

    public func separate(_ input: UnsafeBufferPointer<Float>, into output: UnsafeMutableBufferPointer<Float>) throws {
        let length = segmentFrames
        spec.withUnsafeMutableBufferPointer { spectrogram.forward(input, length: length, into: $0) }
        let mix = try MLMultiArray(shape: [1, 2, NSNumber(value: length)], dataType: .float32)
        mix.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in
            _ = buffer.update(fromContentsOf: input)
        }
        let specArray = try MLMultiArray(
            shape: [1, 4, NSNumber(value: Spectrogram.bins), NSNumber(value: frames)], dataType: .float32
        )
        specArray.withUnsafeMutableBufferPointer(ofType: Float.self) { buffer, _ in
            spec.withUnsafeBufferPointer { _ = buffer.update(fromContentsOf: $0) }
        }
        let features = try MLDictionaryFeatureProvider(dictionary: ["mix": mix, "spec": specArray])
        let result = try model.prediction(from: features)
        guard let time = result.featureValue(for: "time")?.multiArrayValue,
              let freq = result.featureValue(for: "freq")?.multiArrayValue
        else { throw StemModelError.badOutput("missing outputs") }
        // The time branch first, then each source's spectrogram inverted on top of it.
        let timeValues = try Self.contiguous(time, count: sources * 2 * length)
        _ = output.update(fromContentsOf: timeValues)
        let freqValues = try Self.contiguous(freq, count: sources * 4 * Spectrogram.bins * frames)
        freqValues.withUnsafeBufferPointer { spectrogram.inverseAdd($0, sources: sources, length: length, to: output) }
    }

    /// The array's values in row-major order as Float (Core ML may hand back padded strides or half floats).
    static func contiguous(_ array: MLMultiArray, count: Int) throws -> [Float] {
        guard array.count == count else { throw StemModelError.badOutput("\(array.count) values, expected \(count)") }
        let shape = array.shape.map(\.intValue)
        var expected = 1
        var packed = true
        for (dimension, stride) in zip(shape, array.strides.map(\.intValue)).reversed() {
            packed = packed && (dimension == 1 || stride == expected)
            expected *= dimension
        }
        if packed, array.dataType == .float32 {
            return array.withUnsafeBufferPointer(ofType: Float.self) { Array($0.prefix(count)) }
        }
        return (0 ..< count).map { array[$0].floatValue }
    }
}

/// Where the models live and how one arrives (D-97). Besides the update check, the only network use: a model is
/// downloaded when the user presses Download and never otherwise. It is written as "<name>.partial", checked against
/// its SHA-256, unpacked and compiled for this Mac, and only then put in place; a stop, an error or a wrong checksum
/// removes what was written.
public struct StemModelStore: Sendable {
    /// Where a model comes from, and the checksum and size it must have.
    public struct Source: Sendable {
        public let url: URL
        public let sha256: String
        public let bytes: Int64
    }

    public let folder: URL

    public init(folder: URL) {
        self.folder = folder
    }

    /// The models for the Mac (public repository volodya88i/jGlancer-models): `scripts/stems/convert_demucs_coreml.py`,
    /// zipped `.mlpackage`.
    public static func source(for model: StemModelInfo) -> Source {
        let (sha, bytes) = StemModelChecksums.values(of: model)
        let base = "https://github.com/volodya88i/jGlancer-models/releases/download/\(StemModelChecksums.release)/"
        // A constant, valid URL.
        let url = URL(string: base + model.name + "-coreml.zip") ?? URL(fileURLWithPath: "/")
        return Source(url: url, sha256: sha, bytes: bytes)
    }

    /// The compiled model of `model` (it may not exist yet).
    public func compiledURL(_ model: StemModelInfo) -> URL {
        folder.appendingPathComponent(model.name + ".mlmodelc", isDirectory: true)
    }

    /// Whether the model is there (only a checked, compiled download is ever put in place).
    public func isInstalled(_ model: StemModelInfo) -> Bool {
        FileManager.default.fileExists(atPath: compiledURL(model).path)
    }

    /// Bytes the installed model takes (0 if missing).
    public func installedBytes(_ model: StemModelInfo) -> Int64 {
        let enumerator = FileManager.default.enumerator(at: compiledURL(model), includingPropertiesForKeys: [.fileSizeKey])
        var total: Int64 = 0
        while let file = enumerator?.nextObject() as? URL {
            total += Int64((try? file.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
        }
        return total
    }

    public func remove(_ model: StemModelInfo) throws {
        if isInstalled(model) {
            try FileManager.default.removeItem(at: compiledURL(model))
        }
    }

    /// Downloads, checks, unpacks and compiles `model`; `progress` gets the bytes received. Cancelling the task stops
    /// it and removes what was written.
    public func download(_ model: StemModelInfo, progress: @Sendable (Int64) -> Void) async throws {
        let source = Self.source(for: model)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let partial = folder.appendingPathComponent(model.name + ".partial")
        let unpacked = folder.appendingPathComponent(model.name + ".unpacked", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: partial)
            try? FileManager.default.removeItem(at: unpacked)
        }
        let (bytes, response) = try await URLSession.shared.bytes(from: source.url)
        if let http = response as? HTTPURLResponse, !(200 ..< 300).contains(http.statusCode) {
            throw URLError(.badServerResponse)
        }
        FileManager.default.createFile(atPath: partial.path, contents: nil)
        let file = try FileHandle(forWritingTo: partial)
        var buffer = Data()
        var received: Int64 = 0
        do {
            for try await byte in bytes {
                buffer.append(byte)
                if buffer.count >= 1 << 20 {
                    try Task.checkCancellation()
                    try file.write(contentsOf: buffer)
                    received += Int64(buffer.count)
                    buffer.removeAll(keepingCapacity: true)
                    progress(received)
                }
            }
            try file.write(contentsOf: buffer)
            received += Int64(buffer.count)
            progress(received)
            try file.close()
        } catch {
            try? file.close()
            throw error
        }
        guard try Self.sha256(of: partial) == source.sha256 else { throw StemModelError.checksumMismatch }
        try Self.unzip(partial, into: unpacked)
        guard let package = try FileManager.default.contentsOfDirectory(at: unpacked, includingPropertiesForKeys: nil)
            .first(where: { $0.pathExtension == "mlpackage" })
        else { throw StemModelError.unpackFailed }
        let compiled = try await MLModel.compileModel(at: package)
        let target = compiledURL(model)
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: compiled, to: target)
    }

    /// The SHA-256 of a file, lower-case hex.
    public static func sha256(of url: URL) throws -> String {
        try StemChecksum.sha256(of: url)
    }

    /// Unzips with the system's `ditto` (no library needed).
    static func unzip(_ archive: URL, into folder: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", archive.path, folder.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { throw StemModelError.unpackFailed }
    }
}
