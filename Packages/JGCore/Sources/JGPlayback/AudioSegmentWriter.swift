import AVFoundation
import Foundation

/// The audio half of `SegmentExporter`: a composition of the segment, scaled to the speed, read through a mix
/// output (pitch algorithm, fade ramps) as PCM and written with `AVAudioFile` in the format the target's extension
/// names (WAV, AIFF, FLAC, or M4A: ALAC for lossless sources, AAC otherwise).
struct AudioSegmentWriter {
    let request: SegmentExportRequest
    let url: URL

    func write() async throws {
        let asset = AVURLAsset(url: request.source)
        guard let source = try await asset.loadTracks(withMediaType: .audio).first else { throw SegmentExportError.unsupported }
        let format = try await SourceFormat(track: source)
        let composition = AVMutableComposition()
        guard let track = composition.addMutableTrack(withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) else {
            throw SegmentExportError.failed
        }
        let range = CMTimeRange(
            start: SegmentExporter.time(request.range.lowerBound), end: SegmentExporter.time(request.range.upperBound)
        )
        try track.insertTimeRange(range, of: source, at: .zero)
        var length = range.duration
        if request.rate != PlaybackSpeed.normal {
            length = CMTimeMultiplyByFloat64(range.duration, multiplier: 1 / Double(request.rate))
            track.scaleTimeRange(CMTimeRange(start: .zero, duration: range.duration), toDuration: length)
        }
        let reader = try AVAssetReader(asset: composition)
        let rate = format.outputRate(for: url)
        let output = AVAssetReaderAudioMixOutput(audioTracks: [track], audioSettings: format.pcmSettings(rate: rate))
        output.audioTimePitchAlgorithm = request.preservesPitch ? .spectral : .varispeed
        if request.fades {
            output.audioMix = fades(on: track, length: length)
        }
        guard reader.canAdd(output) else { throw SegmentExportError.failed }
        reader.add(output)
        // The time-pitch renderer may run a little past the end: frames beyond the segment are dropped.
        let frames = AVAudioFramePosition((length.seconds * rate).rounded())
        try copy(from: output, of: reader, frames: frames, into: format.fileSettings(for: url))
    }

    /// Reads PCM from `output` into a new file at `url` (closed when this returns).
    private func copy(
        from output: AVAssetReaderOutput, of reader: AVAssetReader, frames limit: AVAudioFramePosition, into settings: [String: Any]
    ) throws {
        let file = try AVAudioFile(forWriting: url, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: true)
        guard reader.startReading() else { throw reader.error ?? SegmentExportError.failed }
        defer { reader.cancelReading() }
        var written: AVAudioFramePosition = 0
        while written < limit, let buffer = output.copyNextSampleBuffer() {
            try Task.checkCancellation()
            let count = AVAudioFrameCount(min(AVAudioFramePosition(CMSampleBufferGetNumSamples(buffer)), limit - written))
            guard count > 0, let pcm = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: count) else { continue }
            pcm.frameLength = count
            let status = CMSampleBufferCopyPCMDataIntoAudioBufferList(
                buffer, at: 0, frameCount: Int32(count), into: pcm.mutableAudioBufferList
            )
            guard status == noErr else { throw SegmentExportError.failed }
            try file.write(from: pcm)
            written += AVAudioFramePosition(count)
        }
        guard reader.status != .failed else { throw reader.error ?? SegmentExportError.failed }
        if #available(macOS 15, *) {
            file.close()
        }
    }

    /// Volume ramps of `fadeSeconds` (at most a quarter of the segment) in and out.
    private func fades(on track: AVCompositionTrack, length: CMTime) -> AVAudioMix {
        let fade = SegmentExporter.time(min(SegmentExporter.fadeSeconds, length.seconds / 4))
        let parameters = AVMutableAudioMixInputParameters(track: track)
        parameters.setVolumeRamp(fromStartVolume: 0, toEndVolume: 1, timeRange: CMTimeRange(start: .zero, duration: fade))
        parameters.setVolumeRamp(fromStartVolume: 1, toEndVolume: 0, timeRange: CMTimeRange(start: length - fade, duration: fade))
        let mix = AVMutableAudioMix()
        mix.inputParameters = [parameters]
        return mix
    }
}

/// What the source is made of: whether it is lossless, its rate, channels and sample format.
private struct SourceFormat {
    let isLossless: Bool
    let sampleRate: Double
    let channels: Int
    let bitDepth: Int
    let isFloat: Bool

    init(track: AVAssetTrack) async throws {
        let description = try await track.load(.formatDescriptions).first
        let basic = description.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee }
        let id = basic?.mFormatID ?? kAudioFormatMPEG4AAC
        isLossless = [kAudioFormatLinearPCM, kAudioFormatAppleLossless, kAudioFormatFLAC].contains(id)
        sampleRate = basic.map(\.mSampleRate).flatMap { $0 > 0 ? $0 : nil } ?? 44100
        channels = min(max(Int(basic?.mChannelsPerFrame ?? 2), 1), 2)
        isFloat = id == kAudioFormatLinearPCM && (basic?.mFormatFlags ?? 0) & kAudioFormatFlagIsFloat != 0
        // PCM states its bits; ALAC and FLAC flag the source depth (1 = 16 bit).
        bitDepth = switch id {
        case kAudioFormatLinearPCM: isFloat ? 32 : (basic?.mBitsPerChannel ?? 16) <= 16 ? 16 : 24
        default: basic?.mFormatFlags == 1 ? 16 : 24
        }
    }

    /// AAC tops out at 48 kHz; every other format keeps the source rate.
    func outputRate(for url: URL) -> Double {
        url.pathExtension.lowercased() == "m4a" && !isLossless ? min(sampleRate, 48000) : sampleRate
    }

    /// What the reader delivers: interleaved float.
    func pcmSettings(rate: Double) -> [String: Any] {
        [
            AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32, AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: rate, AVNumberOfChannelsKey: channels,
        ]
    }

    /// The file's own format, by the extension of `url`.
    func fileSettings(for url: URL) -> [String: Any] {
        let common: [String: Any] = [AVSampleRateKey: outputRate(for: url), AVNumberOfChannelsKey: channels]
        let format: [String: Any] = switch url.pathExtension.lowercased() {
        case "wav":
            [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: bitDepth, AVLinearPCMIsFloatKey: isFloat,
             AVLinearPCMIsBigEndianKey: false, AVLinearPCMIsNonInterleaved: false]
        case "aif", "aiff":
            // AIFF holds integers only.
            [AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: min(bitDepth, 24), AVLinearPCMIsFloatKey: false,
             AVLinearPCMIsBigEndianKey: true, AVLinearPCMIsNonInterleaved: false]
        case "flac":
            [AVFormatIDKey: kAudioFormatFLAC, AVEncoderBitDepthHintKey: min(bitDepth, 24)]
        case _ where isLossless:
            [AVFormatIDKey: kAudioFormatAppleLossless, AVEncoderBitDepthHintKey: min(bitDepth, 24)]
        default:
            [AVFormatIDKey: kAudioFormatMPEG4AAC, AVEncoderBitRateKey: SegmentExporter.aacBitRate]
        }
        return common.merging(format) { $1 }
    }
}
