import AVFoundation
import CoreML
import Foundation

/// One song to split (D-97): what to write and where.
public struct StemJob: Identifiable, Sendable {
    public let id = UUID()
    public let song: URL
    public let model: StemModelInfo
    public let stems: [StemKind]
    /// The folder the stems go to; `makesFolder` when the job creates it (removed again if the job fails).
    public let folder: URL
    public let makesFolder: Bool

    public init(song: URL, model: StemModelInfo, stems: [StemKind], folder: URL, makesFolder: Bool) {
        self.song = song
        self.model = model
        self.stems = stems
        self.folder = folder
        self.makesFolder = makesFolder
    }
}

/// Runs a `StemJob` off the main thread: decodes the song, runs Demucs piece by piece, writes 24-bit WAV stems as
/// ".partial" files and renames them at the end (never over an existing file: "… 2"). Stop or an error removes the
/// partial files and a folder the job made. The song itself is only read.
public enum StemJobRunner {
    /// The finished files, in the window's order.
    public static func run(
        _ job: StemJob, compiledModel: URL, progress: @escaping @Sendable (Double) -> Void,
        isCancelled: @escaping @Sendable () -> Bool
    ) throws -> [URL] {
        let song = try StemAudioDecoder.decode(job.song, sampleRate: job.model.sampleRate)
        if isCancelled() {
            throw StemSplitCancelled()
        }
        let separator: StemSeparator = job.model.network == .vocals
            ? try RoFormerStemSeparator(compiledModel: compiledModel, info: job.model)
            : try CoreMLStemSeparator(compiledModel: compiledModel, info: job.model)
        return try write(job, song: song, separator: separator, progress: progress, isCancelled: isCancelled)
    }

    /// Splits the decoded song with `separator` and writes the job's stems (the tests pass a stand-in network).
    static func write(
        _ job: StemJob, song: (left: [Float], right: [Float]), separator: StemSeparator,
        progress: @escaping @Sendable (Double) -> Void, isCancelled: @escaping @Sendable () -> Bool
    ) throws -> [URL] {
        let fileManager = FileManager.default
        if job.makesFolder {
            try fileManager.createDirectory(at: job.folder, withIntermediateDirectories: true)
        }
        var writers: [PartialStem] = []
        do {
            for stem in job.stems {
                let partial = job.folder.appendingPathComponent(StemNaming.fileName(for: job.song, stem: stem) + ".partial")
                try writers.append(PartialStem(
                    stem: stem,
                    writer: WaveStemWriter(url: partial, sampleRate: job.model.sampleRate),
                    partial: partial
                ))
            }
            let outputs = writers.compactMap { entry in
                job.model.part(of: entry.stem).map { StemOutput($0, to: entry.writer) }
            }
            try StemSplitter.split(
                left: song.left,
                right: song.right,
                separator: separator,
                outputs: outputs,
                progress: progress,
                isCancelled: isCancelled
            )
            var finished: [URL] = []
            for entry in writers {
                try entry.writer.complete()
                let target = free(job.folder.appendingPathComponent(StemNaming.fileName(for: job.song, stem: entry.stem)))
                try fileManager.moveItem(at: entry.partial, to: target)
                finished.append(target)
            }
            return finished
        } catch {
            discard(writers, of: job)
            throw error
        }
    }

    /// After a stop or an error: the partial files go, and the folder the job made if nothing else is in it.
    private static func discard(_ writers: [PartialStem], of job: StemJob) {
        let fileManager = FileManager.default
        for entry in writers {
            entry.writer.abandon()
            try? fileManager.removeItem(at: entry.partial)
        }
        if job.makesFolder, (try? fileManager.contentsOfDirectory(atPath: job.folder.path))?.isEmpty == true {
            try? fileManager.removeItem(at: job.folder)
        }
    }

    /// A stem being written, and its ".partial" file.
    private struct PartialStem {
        let stem: StemKind
        let writer: WaveStemWriter
        let partial: URL
    }

    /// `url`, or "name 2.wav", "name 3.wav"… when taken.
    static func free(_ url: URL) -> URL {
        var candidate = url
        var number = 2
        let base = url.deletingPathExtension().lastPathComponent
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = url.deletingLastPathComponent().appendingPathComponent("\(base) \(number).\(url.pathExtension)")
            number += 1
        }
        return candidate
    }
}

/// Reads a song as stereo float samples at the model's rate (mono is doubled; other rates are converted).
public enum StemAudioDecoder {
    public enum DecodeError: Error {
        case unsupported
    }

    public static func decode(_ url: URL, sampleRate: Int) throws -> (left: [Float], right: [Float]) {
        let file = try AVAudioFile(forReading: url)
        guard let target = AVAudioFormat(
            commonFormat: .pcmFormatFloat32, sampleRate: Double(sampleRate), channels: 2, interleaved: false
        ), let converter = AVAudioConverter(from: file.processingFormat, to: target)
        else { throw DecodeError.unsupported }
        if file.processingFormat.channelCount == 1 {
            converter.channelMap = [0, 0]
        }
        let ratio = Double(sampleRate) / file.processingFormat.sampleRate
        let capacity = AVAudioFrameCount(Double(file.length) * ratio) + 4096
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity),
              let input = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 65536)
        else { throw DecodeError.unsupported }
        var readError: Error?
        var finished = false
        var conversionError: NSError?
        while !finished {
            guard let chunk = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 65536) else { break }
            let status = converter.convert(to: chunk, error: &conversionError) { _, outStatus in
                // Reading past the end throws: stop at the end instead.
                input.frameLength = 0
                if file.framePosition < file.length {
                    do {
                        try file.read(into: input)
                    } catch {
                        readError = error
                    }
                }
                if input.frameLength == 0 || readError != nil {
                    outStatus.pointee = .endOfStream
                    return nil
                }
                outStatus.pointee = .haveData
                return input
            }
            append(chunk, to: output)
            finished = status == .endOfStream || status == .error || chunk.frameLength == 0
        }
        if let error = readError ?? conversionError {
            throw error
        }
        guard let channels = output.floatChannelData else { throw DecodeError.unsupported }
        let count = Int(output.frameLength)
        return (Array(UnsafeBufferPointer(start: channels[0], count: count)),
                Array(UnsafeBufferPointer(start: channels[1], count: count)))
    }

    private static func append(_ chunk: AVAudioPCMBuffer, to output: AVAudioPCMBuffer) {
        guard let from = chunk.floatChannelData, let to = output.floatChannelData else { return }
        let frames = min(Int(chunk.frameLength), Int(output.frameCapacity - output.frameLength))
        let start = Int(output.frameLength)
        for channel in 0 ..< 2 {
            (to[channel] + start).update(from: from[channel], count: frames)
        }
        output.frameLength += AVAudioFrameCount(frames)
    }
}
