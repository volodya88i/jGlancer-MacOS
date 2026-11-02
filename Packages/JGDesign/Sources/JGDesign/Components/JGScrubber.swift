import AppKit
import QuartzCore
import SwiftUI

/// The playback scrubber (docs/DESIGN.md §6): a plain slider track (video) or a waveform (audio), the
/// played part brighter, and a bold `text.primary` playhead with an accent glow.
///
/// Built on layers: moving the playhead changes two layer frames, nothing is redrawn. Feed it a `JGLiveTime`
/// so playback updates never go through SwiftUI; a plain `time` suits static uses.
/// Click or drag to seek (`onSeek(seconds, isFinal)`: false while dragging, true on release); VoiceOver sees
/// an adjustable slider. Keyboard seeking belongs to the player.
/// With `segment(_:onChange:)` accent brackets mark a segment and drag its ends; `zoomable` lets the user zoom
/// (⌘-wheel, pinch, vertical trackpad scroll) and scroll (⇧-wheel, horizontal scroll) the timeline (D-73).
public struct JGScrubber: NSViewRepresentable {
    private let time: Double
    private let liveTime: JGLiveTime?
    private let duration: Double
    private let waveform: JGWaveformPeaks?
    private let accessibilityLabel: String
    private let onSeek: (Double, Bool) -> Void
    private var segment: ClosedRange<Double>?
    private var onSegmentChange: ((ClosedRange<Double>, JGSegmentEdge, Bool) -> Void)?
    private var isZoomable = false
    private var detail: JGWaveformDetail?
    private var onWindowChange: ((ClosedRange<Double>) -> Void)?
    private var segmentMenu: (() -> NSMenu?)?
    private var animatesPlayhead = true
    private var wheelZooms = false
    private var waveformHeight: CGFloat = 1
    private var animatesWaveform = false

    public init(
        time: Double, duration: Double, waveform: JGWaveformPeaks? = nil, accessibilityLabel: String,
        onSeek: @escaping (Double, Bool) -> Void
    ) {
        self.time = time
        liveTime = nil
        self.duration = duration
        self.waveform = waveform
        self.accessibilityLabel = accessibilityLabel
        self.onSeek = onSeek
    }

    /// A scrubber whose playhead follows `liveTime`.
    public init(
        liveTime: JGLiveTime, duration: Double, waveform: JGWaveformPeaks? = nil, accessibilityLabel: String,
        onSeek: @escaping (Double, Bool) -> Void
    ) {
        time = liveTime.seconds
        self.liveTime = liveTime
        self.duration = duration
        self.waveform = waveform
        self.accessibilityLabel = accessibilityLabel
        self.onSeek = onSeek
    }

    public func makeNSView(context _: Context) -> ScrubberView {
        ScrubberView()
    }

    public func updateNSView(_ view: ScrubberView, context _: Context) {
        view.duration = duration
        view.waveform = waveform
        view.allowsZoom = isZoomable
        view.detail = detail
        view.onWindowChange = onWindowChange
        view.segment = segment
        view.onSegmentChange = onSegmentChange
        view.segmentMenu = segmentMenu
        view.animatesPlayhead = animatesPlayhead
        view.wheelZooms = wheelZooms
        view.waveformHeight = waveformHeight
        view.animatesWaveform = animatesWaveform
        if let liveTime {
            liveTime.attach(view)
            view.time = liveTime.seconds
            view.playbackRate = liveTime.rate
        } else {
            view.time = time
        }
        view.onSeek = onSeek
        if view.accessibilityLabel() != accessibilityLabel {
            view.setAccessibilityLabel(accessibilityLabel)
        }
    }
}

public extension JGScrubber {
    /// Accent brackets around `segment` (nil: none); dragging an end reports the new segment, the dragged end and
    /// whether the drag is over.
    func segment(
        _ segment: ClosedRange<Double>?, onChange: @escaping (ClosedRange<Double>, JGSegmentEdge, Bool) -> Void
    ) -> JGScrubber {
        var copy = self
        copy.segment = segment
        copy.onSegmentChange = onChange
        return copy
    }

    /// The waveform's share of the height (½ for the narrow style) and whether a new one morphs in (D-79).
    func waveformStyle(height: CGFloat, animates: Bool) -> JGScrubber {
        var copy = self
        copy.waveformHeight = height
        copy.animatesWaveform = animates
        return copy
    }

    /// False stops the smooth playhead motion (a scrubber faded out but still in the window).
    func animatesPlayhead(_ isOn: Bool) -> JGScrubber {
        var copy = self
        copy.animatesPlayhead = isOn
        return copy
    }

    /// The menu of a right click (or Control-click) inside the segment.
    func segmentMenu(_ make: @escaping () -> NSMenu?) -> JGScrubber {
        var copy = self
        copy.segmentMenu = make
        return copy
    }

    /// Lets the user zoom and scroll the timeline; `onWindowChange` reports the shown part (to load `detail`).
    /// Turning it off shows the whole timeline again.
    /// `wheelZooms`: the mouse wheel alone zooms (otherwise ⌘ is needed).
    func zoomable(
        _ isOn: Bool, wheelZooms: Bool = false, detail: JGWaveformDetail? = nil,
        onWindowChange: ((ClosedRange<Double>) -> Void)? = nil
    ) -> JGScrubber {
        var copy = self
        copy.isZoomable = isOn
        copy.wheelZooms = wheelZooms
        copy.detail = detail
        copy.onWindowChange = onWindowChange
        return copy
    }
}

#Preview {
    let peaks = (0 ..< 512).map { index in Float(sin(Double(index) / 9) * (0.3 + 0.6 * Double(index % 64) / 64)) }
    VStack(spacing: JGSpacing.l) {
        JGScrubber(time: 95, duration: 300, accessibilityLabel: "Position") { _, _ in }
            .frame(height: JGMetrics.controlHeightCompact)
        JGScrubber(
            time: 120, duration: 300, waveform: JGWaveformPeaks(lows: peaks.map { -abs($0) }, highs: peaks.map(abs)),
            accessibilityLabel: "Position"
        ) { _, _ in }
            .frame(height: JGMetrics.waveformHeight)
    }
    .frame(width: 480)
    .padding(JGSpacing.l)
    .background(JGColor.bgMedia)
}
