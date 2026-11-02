import AVFoundation
import Foundation
import JGPlayback
import JGThumbs

/// Player benchmark (PLAN Phase 4): video open → playing, CPU while a video plays with its controls shown and
/// hidden, the effective rate at 2×, the waveform of a long song, CPU while audio plays, and idle
/// CPU after leaving the viewer. Informational (DECISIONS D-42); run muted (`-JGMute YES`).
@MainActor
enum PlaybackBenchmark {
    struct Result: Codable {
        var openVideoMs: Double?
        var openVideoWarmMs: Double?
        var videoCPUWithControlsPercent = 0.0
        var videoCPUPercent = 0.0
        var rateAtDoubleSpeed: Double?
        var waveformMs: Double?
        var audioCPUPercent = 0.0
        var idleCPUAfterPercent = 0.0
        var footprintMB = 0.0
    }

    static func run(appModel: AppModel, video: URL, audio: URL?, output: URL) async {
        var result = Result()
        let playback = appModel.playback
        result.openVideoMs = await timeToPlaying(appModel, video)
        // Again in the same process: AVFoundation and the audio output are set up by then.
        appModel.closeViewer()
        try? await Task.sleep(for: .milliseconds(500))
        result.openVideoWarmMs = await timeToPlaying(appModel, video)
        if let viewer = appModel.mediaViewer {
            // The controls hide after 2.5 s of rest; then they are shown again (and stay: no pointer activity).
            _ = await waitUntil(4) { !viewer.isChromeVisible }
            result.videoCPUPercent = await Benchmark.idleCPUPercent(over: 4)
            viewer.isChromeVisible = true
            try? await Task.sleep(for: .milliseconds(500))
            result.videoCPUWithControlsPercent = await Benchmark.idleCPUPercent(over: 3)
            viewer.setRate(2)
            try? await Task.sleep(for: .milliseconds(300))
            let before = (playback.player.currentTime().seconds, Date())
            try? await Task.sleep(for: .seconds(2))
            result.rateAtDoubleSpeed = (playback.player.currentTime().seconds - before.0) / Date().timeIntervalSince(before.1)
            viewer.setRate(PlaybackSpeed.normal)
            result.footprintMB = Benchmark.footprintMB()
        }
        if let audio {
            result.waveformMs = await waveformMilliseconds(audio)
            await appModel.open([audio])
            try? await Task.sleep(for: .seconds(1))
            result.audioCPUPercent = await Benchmark.idleCPUPercent(over: 3)
        }
        appModel.closeViewer()
        try? await Task.sleep(for: .seconds(1))
        result.idleCPUAfterPercent = await Benchmark.idleCPUPercent(over: 3)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(result).write(to: output)
        try? Data(summary(result).utf8).write(to: output.deletingPathExtension().appendingPathExtension("txt"))
    }

    /// Milliseconds from opening a file until it plays (time advancing), or nil after 5 s.
    private static func timeToPlaying(_ appModel: AppModel, _ url: URL) async -> Double? {
        let playback = appModel.playback
        let start = Date()
        await appModel.open([url])
        let started = await waitUntil(5) { playback.isPlaying && playback.player.currentTime().seconds > 0.05 }
        return started ? Date().timeIntervalSince(start) * 1000 : nil
    }

    /// A fresh decode (no cache) until the waveform is complete.
    private static func waveformMilliseconds(_ url: URL) async -> Double? {
        let start = Date()
        var complete = false
        for await waveform in WaveformService(disk: nil).waveform(for: WaveformRequest(url: url, assetID: nil, modifiedAt: nil)) {
            complete = waveform.isComplete
        }
        return complete ? Date().timeIntervalSince(start) * 1000 : nil
    }

    private static func waitUntil(_ seconds: Double, _ condition: () -> Bool) async -> Bool {
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(5))
        }
        return condition()
    }

    static func summary(_ result: Result) -> String {
        func value(_ number: Double?, _ format: String) -> String {
            number.map { String(format: format, $0) } ?? "n/a"
        }
        return [
            "open video → playing: \(value(result.openVideoMs, "%.0f ms")) first, \(value(result.openVideoWarmMs, "%.0f ms")) warm",
            String(format: "CPU, 1080p video, controls shown: %.1f %%", result.videoCPUWithControlsPercent),
            String(format: "CPU, 1080p video, controls hidden: %.1f %%", result.videoCPUPercent),
            "effective rate at 2×: \(value(result.rateAtDoubleSpeed, "%.2f"))",
            "waveform of a 5-minute song: \(value(result.waveformMs, "%.0f ms"))",
            String(format: "CPU, audio with waveform: %.1f %%", result.audioCPUPercent),
            String(
                format: "idle CPU after closing: %.2f %% (target 1) %@", result.idleCPUAfterPercent,
                Benchmark.verdict(result.idleCPUAfterPercent, 1)
            ),
            String(format: "memory: %.0f MB", result.footprintMB),
        ].joined(separator: "\n") + "\n"
    }
}
