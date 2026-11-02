#!/usr/bin/env -S swift -suppress-warnings
// Generates media for the playback benchmark (scripts/bench.sh): a 60 s 1080p30 H.264 clip with an AAC tone and a
// 5-minute AAC song with a changing envelope (for the waveform).
//
// Usage: scripts/make_playback_media.swift [output-dir]   Default: $TMPDIR/jGlancer-playback-bench
//
// Safety: writes only inside the output directory. A non-empty directory is used only if it carries the marker
// file this script leaves behind.

import AVFoundation
import CoreGraphics
import Foundation

let markerName = ".jglancer-generated"
let output = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : NSTemporaryDirectory() + "jGlancer-playback-bench")
let fileManager = FileManager.default

struct ScriptError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) {
        self.description = description
    }
}

func prepareOutput() throws {
    var isDirectory: ObjCBool = false
    if fileManager.fileExists(atPath: output.path, isDirectory: &isDirectory) {
        let contents = try fileManager.contentsOfDirectory(atPath: output.path)
        guard isDirectory.boolValue, contents.isEmpty || contents.contains(markerName) else {
            throw ScriptError("\(output.path) is not empty and was not created by this script")
        }
    }
    try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
    try Data().write(to: output.appendingPathComponent(markerName))
}

/// Moving colored stripes and a progress line, with a quiet tone; audio is written alongside each frame so the
/// writer can interleave the tracks.
func writeClip(to url: URL, width: Int, height: Int, fps: Int32, seconds: Int) async throws {
    try? fileManager.removeItem(at: url)
    let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)
    let video = AVAssetWriterInput(mediaType: .video, outputSettings: [
        AVVideoCodecKey: AVVideoCodecType.h264, AVVideoWidthKey: width, AVVideoHeightKey: height,
    ])
    let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: video, sourcePixelBufferAttributes: [
        kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        kCVPixelBufferWidthKey as String: width, kCVPixelBufferHeightKey as String: height,
    ])
    let audio = AVAssetWriterInput(mediaType: .audio, outputSettings: [
        AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 1,
    ])
    writer.add(video)
    writer.add(audio)
    guard writer.startWriting(), let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 1) else {
        throw ScriptError("cannot start writing \(url.lastPathComponent)")
    }
    writer.startSession(atSourceTime: .zero)
    var description: CMAudioFormatDescription?
    CMAudioFormatDescriptionCreate(
        allocator: nil, asbd: format.streamDescription, layoutSize: 0, layout: nil, magicCookieSize: 0,
        magicCookie: nil, extensions: nil, formatDescriptionOut: &description
    )
    let samplesPerFrame = 44100 / Int(fps)
    let frames = seconds * Int(fps)
    for frame in 0 ..< frames {
        while !video.isReadyForMoreMediaData {
            try await Task.sleep(for: .milliseconds(1))
        }
        guard let pool = adaptor.pixelBufferPool else { throw ScriptError("no pixel buffer pool") }
        var pixelBuffer: CVPixelBuffer?
        CVPixelBufferPoolCreatePixelBuffer(nil, pool, &pixelBuffer)
        guard let pixelBuffer else { throw ScriptError("no pixel buffer") }
        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let context = CGContext(
            data: CVPixelBufferGetBaseAddress(pixelBuffer), width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer), space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) {
            let stripe = width / 8
            for index in 0 ... 8 {
                let hue = CGFloat(index) / 8 * 6.28
                context.setFillColor(CGColor(
                    red: 0.5 + 0.5 * sin(hue),
                    green: 0.5 + 0.5 * sin(hue + 2),
                    blue: 0.5 + 0.5 * sin(hue + 4),
                    alpha: 1
                ))
                context.fill(CGRect(x: (index * stripe + frame * 6) % (width + stripe) - stripe, y: 0, width: stripe, height: height))
            }
            context.setFillColor(CGColor(gray: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: height / 2 - 3, width: width * frame / frames, height: 6))
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])
        adaptor.append(pixelBuffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: fps))

        while !audio.isReadyForMoreMediaData {
            try await Task.sleep(for: .milliseconds(1))
        }
        guard let pcm = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samplesPerFrame)),
              let channel = pcm.floatChannelData?[0]
        else { throw ScriptError("no audio buffer") }
        pcm.frameLength = AVAudioFrameCount(samplesPerFrame)
        let start = frame * samplesPerFrame
        for index in 0 ..< samplesPerFrame {
            channel[index] = 0.1 * sinf(Float(start + index) * 2 * .pi * 330 / 44100)
        }
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 44100), presentationTimeStamp: CMTime(value: CMTimeValue(start), timescale: 44100),
            decodeTimeStamp: .invalid
        )
        var sample: CMSampleBuffer?
        CMSampleBufferCreate(
            allocator: nil, dataBuffer: nil, dataReady: false, makeDataReadyCallback: nil, refcon: nil,
            formatDescription: description, sampleCount: samplesPerFrame, sampleTimingEntryCount: 1,
            sampleTimingArray: &timing, sampleSizeEntryCount: 0, sampleSizeArray: nil, sampleBufferOut: &sample
        )
        guard let sample else { throw ScriptError("no audio sample buffer") }
        CMSampleBufferSetDataBufferFromAudioBufferList(
            sample, blockBufferAllocator: nil, blockBufferMemoryAllocator: nil, flags: 0, bufferList: pcm.audioBufferList
        )
        audio.append(sample)
    }
    video.markAsFinished()
    audio.markAsFinished()
    await writer.finishWriting()
    guard writer.status == .completed else { throw writer.error ?? ScriptError("writing \(url.lastPathComponent) failed") }
}

/// A stereo AAC "song": notes changing every second under a slowly swelling envelope, written a second at a time.
func writeSong(to url: URL, seconds: Int) throws {
    try? fileManager.removeItem(at: url)
    guard let format = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2) else { throw ScriptError("no format") }
    let file = try AVAudioFile(
        forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44100, AVNumberOfChannelsKey: 2],
        commonFormat: .pcmFormatFloat32, interleaved: false
    )
    guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44100) else { throw ScriptError("no buffer") }
    buffer.frameLength = 44100
    for second in 0 ..< seconds {
        let note = 220 + 55 * Double(second % 8)
        for channel in 0 ..< 2 {
            guard let samples = buffer.floatChannelData?[channel] else { continue }
            for index in 0 ..< 44100 {
                let time = Double(second) + Double(index) / 44100
                let envelope = 0.1 + 0.6 * abs(sin(time * 0.2)) * (0.6 + 0.4 * sin(time * 5))
                samples[index] = Float(envelope * sin(2 * .pi * note * time))
            }
        }
        try file.write(from: buffer)
    }
}

do {
    try prepareOutput()
    try await writeClip(to: output.appendingPathComponent("clip-1080p.mp4"), width: 1920, height: 1080, fps: 30, seconds: 60)
    try writeSong(to: output.appendingPathComponent("song-5min.m4a"), seconds: 300)
    print("playback media: \(output.path)")
} catch {
    FileHandle.standardError.write(Data("error: \(error)\n".utf8))
    exit(1)
}
