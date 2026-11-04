import AppKit
import Testing
@testable import JGDesign

@MainActor
struct ScrubberTests {
    private func mouse(_ type: NSEvent.EventType, x: CGFloat) throws -> NSEvent {
        try #require(NSEvent.mouseEvent(
            with: type, location: NSPoint(x: x, y: 5), modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
    }

    @Test func thePlainTrackStaysRoundAndInside() {
        let bounds = CGRect(x: 0, y: 0, width: 640, height: 28)
        #expect(ScrubberView.sliderPath(width: 640, in: bounds).boundingBox == CGRect(x: 0, y: 12, width: 640, height: 4))
        #expect(ScrubberView.sliderPath(width: 0, in: bounds).boundingBox.width == JGMetrics.sliderThickness)
    }

    @Test func waveformStaysInsideItsBoundsAndShowsSilence() {
        let bounds = CGRect(x: 0, y: 0, width: 300, height: 80)
        let loud = JGWaveformPeaks(lows: [-0.2, -0.5, -0.1], highs: [0.3, 0.5, 0.1])
        let box = ScrubberView.waveformPath(loud, in: bounds).boundingBox
        #expect(box.minY >= -0.01 && box.maxY <= 80.01)
        #expect(box.height > 70)
        let silent = JGWaveformPeaks(lows: [0, 0], highs: [0, 0])
        #expect(!ScrubberView.waveformPath(silent, in: bounds).isEmpty)
    }

    @Test func dragSeeksContinuouslyAndReleaseIsFinal() throws {
        let view = ScrubberView(frame: NSRect(x: 0, y: 0, width: 200, height: 28))
        view.duration = 100
        var seeks: [(Double, Bool)] = []
        view.onSeek = { seeks.append(($0, $1)) }
        #expect(!view.mouseDownCanMoveWindow)
        try view.mouseDown(with: mouse(.leftMouseDown, x: 50))
        view.time = 90 // playback reports while dragging: ignored
        try view.mouseDragged(with: mouse(.leftMouseDragged, x: 300))
        try view.mouseUp(with: mouse(.leftMouseUp, x: 150))
        #expect(seeks.map(\.0) == [25, 100, 75])
        #expect(seeks.map(\.1) == [false, false, true])
        #expect(!view.isScrubbing)
    }

    @Test func windowZoomsAroundAnAnchorAndStaysInsideTheFile() {
        var window = ScrubberWindow(duration: 100)
        #expect(!window.isZoomed)
        window.zoom(by: 4, around: 50)
        #expect(window.length == 25)
        #expect(window.start == 37.5) // 50 stays in the middle
        window.scroll(by: 1000)
        #expect(window.end == 100)
        window.zoom(by: 1000, around: 90)
        #expect(window.length == ScrubberWindow.minimumLength)
        window.zoom(by: 0.000_1, around: 90)
        #expect(window == ScrubberWindow(duration: 100))
        #expect(window.time(at: 50, width: 100) == 50)
    }

    @Test func zoomedWaveformCoversTheWindowOnly() {
        let bounds = CGRect(x: 0, y: 0, width: 400, height: 80)
        var window = ScrubberWindow(duration: 100)
        window.zoom(by: 50, around: 10) // 2 s around 10 s
        // Loud only in the first second: zoomed into 50…52 s the coarse peaks are silent, the detail is loud.
        let coarse = JGWaveformPeaks(lows: [-1] + Array(repeating: 0, count: 99), highs: [1] + Array(repeating: 0, count: 99))
        window.scroll(by: 40)
        let quiet = ScrubberView.waveformPath(coarse, duration: 100, visible: window, in: bounds).boundingBox
        let half = Array(repeating: Float(0.5), count: 40) // 0.1 s buckets, finer than the coarse 1 s
        let detail = JGWaveformDetail(range: 49 ... 53, peaks: JGWaveformPeaks(lows: half.map { -$0 }, highs: half))
        let loud = ScrubberView.waveformPath(coarse, detail: detail, duration: 100, visible: window, in: bounds).boundingBox
        #expect(quiet.height < 2)
        #expect(abs(loud.height - 40) < 1) // half the loudest peak of the file
    }

    @Test func segmentEndsDragWithinTheFile() throws {
        let view = ScrubberView(frame: NSRect(x: 0, y: 0, width: 202, height: 28))
        view.duration = 100
        view.segment = 20 ... 60
        struct Change {
            let segment: ClosedRange<Double>
            let edge: JGSegmentEdge
            let isFinal: Bool
        }
        var changes: [Change] = []
        var seeks = 0
        view.onSegmentChange = { changes.append(Change(segment: $0, edge: $1, isFinal: $2)) }
        view.onSeek = { _, _ in seeks += 1 }
        // The `[` at 20 s is at x 40; dragging it past the end stops short of it.
        try view.mouseDown(with: mouse(.leftMouseDown, x: 41))
        try view.mouseDragged(with: mouse(.leftMouseDragged, x: 190))
        try view.mouseUp(with: mouse(.leftMouseUp, x: 101))
        #expect(changes.map(\.edge) == [.start, .start, .start])
        #expect(changes.map(\.isFinal) == [false, false, true])
        #expect(try abs(#require(changes.dropLast().last).segment.lowerBound - (60 - ScrubberView.minimumSegment)) < 0.001)
        #expect(view.segment == 50 ... 60)
        #expect(seeks == 0)
        // Away from the brackets a click seeks.
        try view.mouseDown(with: mouse(.leftMouseDown, x: 150))
        try view.mouseUp(with: mouse(.leftMouseUp, x: 150))
        #expect(seeks == 2)
    }

    @Test func theSegmentHasItsOwnMenu() throws {
        let view = ScrubberView(frame: NSRect(x: 0, y: 0, width: 202, height: 28))
        view.duration = 100
        view.segment = 20 ... 60
        view.segmentMenu = { NSMenu(title: "segment") }
        #expect(try view.menu(for: mouse(.rightMouseDown, x: 80))?.title == "segment")
        #expect(try view.menu(for: mouse(.rightMouseDown, x: 160)) == nil)
    }

    @Test func playheadMovesOnBetweenReportsAndNeverDriftsBack() async throws {
        let view = ScrubberView(frame: NSRect(x: 0, y: 0, width: 200, height: 28))
        let window = NSWindow(contentRect: view.frame, styleMask: [], backing: .buffered, defer: true)
        window.contentView = view
        view.duration = 100
        view.time = 10
        view.playbackRate = 2
        try await Task.sleep(for: .milliseconds(100))
        let moved = view.motion.time
        #expect(moved > 10.1 && moved < 11) // about 0.2 s at 2×
        view.time = moved - 0.05 // a report a little behind: no step back
        #expect(view.motion.time >= moved)
        view.time = 50 // a seek
        #expect(abs(view.motion.time - 50) < 0.1)
        view.playbackRate = 0
        let paused = view.motion.time
        try await Task.sleep(for: .milliseconds(50))
        #expect(view.motion.time == paused)
    }

    @Test func waveformMorphsColumnByColumnWithAnOvershoot() {
        #expect(WaveformMorph.easeOutBack(0) == 0)
        #expect(abs(WaveformMorph.easeOutBack(1) - 1) < 0.000_001)
        #expect(WaveformMorph.easeOutBack(0.6) > 1) // overshoots, then settles
        let view = ScrubberView(frame: NSRect(x: 0, y: 0, width: 100, height: 40))
        let morph = WaveformMorph()
        let flat = WaveColumns(tops: Array(repeating: 0, count: 100), bottoms: Array(repeating: 0, count: 100))
        let loud = WaveColumns(tops: Array(repeating: 1, count: 100), bottoms: Array(repeating: -1, count: 100))
        morph.jump(to: flat)
        morph.morph(to: loud, view: view, selector: #selector(ScrubberView.morphTick))
        #expect(morph.isRunning)
        let start = CACurrentMediaTime()
        let early = morph.frame(at: start + 0.2)
        #expect(early.tops[0] > 0.5) // the first column is well on its way
        #expect(early.tops[99] == 0) // the last one starts 0.27 s later
        #expect(morph.frame(at: start + 1) == loud)
        morph.stop()
        #expect(!morph.isRunning)
    }

    @Test func waveformsFillTheHeight() {
        let bounds = CGRect(x: 0, y: 0, width: 50, height: 80)
        let loud = WaveColumns(tops: Array(repeating: 1, count: 50), bottoms: Array(repeating: -1, count: 50))
        #expect(abs(ScrubberView.wavePath(loud, in: bounds).boundingBox.height - 80) < 0.5)
    }
}
