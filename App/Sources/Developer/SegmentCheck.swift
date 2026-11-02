import AppKit
import AVFoundation
import JGDesign
import JGPlayback

/// `-JGSegmentCheck <folder>` with `-JGOpen <video or song>`: turns on segment selection, zooms the scrubber with a
/// synthetic ⌘-wheel event, snapshots `segment.png`, saves the segment into the folder as the export button would,
/// and logs the segment, the finer peaks (audio) and the saved file.
@MainActor
enum SegmentCheck {
    static func run(appModel: AppModel, window: NSWindow?, folder: URL) async {
        try? await Task.sleep(for: .milliseconds(800))
        guard let model = appModel.mediaViewer, let window else {
            log("no player")
            return
        }
        model.toggleSegmentMode()
        log("segment: \(model.segment.map(SegmentControls.label) ?? "none")")
        try? await Task.sleep(for: .milliseconds(300))
        DeveloperHooks.snapshot(window, to: folder.appendingPathComponent("segment-start.png"))
        if let scrubber = window.contentView.flatMap(find), let segment = model.segment {
            // Over the segment's start, as a pointer would be.
            let width = scrubber.bounds.width
            let duration = model.playback.duration ?? 1
            let x = width * CGFloat(segment.lowerBound / duration) + 40
            let point = scrubber.convert(CGPoint(x: x, y: scrubber.bounds.midY), to: nil)
            for _ in 0 ..< 4 {
                scrubber.scrollWheel(with: commandWheel(at: point))
            }
            log("zoomed the scrubber")
        }
        try? await Task.sleep(for: .milliseconds(600))
        log("finer peaks: \(model.waveformDetail.map { "\($0.range), \($0.peaks.highs.count) buckets" } ?? "none")")
        DeveloperHooks.snapshot(window, to: folder.appendingPathComponent("segment.png"))
        log("menu: \(SegmentMenu.make(for: model)?.items.map(\.title).joined(separator: ", ") ?? "none")")
        if model.kind == .video {
            model.showMessage = { log("toast: \($0)") }
            model.perform(.saveFrame)
            try? await Task.sleep(for: .milliseconds(800))
        }
        await checkStop(model)
        guard let request = model.segmentExport else {
            log("nothing to export")
            return
        }
        do {
            let saved = try await SegmentExporter.save(
                request, to: folder.appendingPathComponent(SegmentExporter.suggestedName(for: request))
            )
            let seconds = try await AVURLAsset(url: saved).load(.duration).seconds
            log("saved \(saved.lastPathComponent), \(String(format: "%.2f", seconds)) s")
        } catch {
            log("export failed: \(error)")
        }
    }

    /// A one-second segment from the playhead, played: it should stop at the end bracket.
    private static func checkStop(_ model: MediaViewerModel) async {
        let start = model.playback.currentTime
        model.setSegment(start ... start + 1, edge: .end, isFinal: true)
        model.playback.pause()
        try? await Task.sleep(for: .milliseconds(300))
        model.togglePlayInSegment() // as the Play button does: a video stands on the end bracket, so from the start
        try? await Task.sleep(for: .milliseconds(1800))
        let time = String(format: "%.2f", model.playback.currentTime)
        log("after playing the segment: playing \(model.playback.isPlaying), at \(time) of end \(String(format: "%.2f", start + 1))")
        model.togglePlayInSegment()
        try? await Task.sleep(for: .milliseconds(300))
        log("play again starts at the segment: \(model.playback.isPlaying), at \(String(format: "%.2f", model.playback.currentTime))")
        model.playback.pause()
    }

    private static func find(_ view: NSView) -> ScrubberView? {
        if let scrubber = view as? ScrubberView {
            return scrubber
        }
        return view.subviews.lazy.compactMap(find).first
    }

    /// Wheel lines up with ⌘ held (zooms in), at `point` of the window. A synthetic event has no window, so its
    /// location in the window is its screen location: the window point goes there.
    private static func commandWheel(at point: CGPoint) -> NSEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .line, wheelCount: 1, wheel1: 3, wheel2: 0, wheel3: 0)
        event?.flags = .maskCommand
        event?.location = CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.height ?? 0) - point.y)
        return event.flatMap(NSEvent.init(cgEvent:)) ?? NSEvent()
    }

    private static func log(_ line: String) {
        FileHandle.standardError.write(Data("segment check: \(line)\n".utf8))
    }
}
