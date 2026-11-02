import AppKit
import QuartzCore
import SwiftUI

/// The AppKit view behind `JGScrubber`.
public final class ScrubberView: NSView {
    var duration: Double = 0 {
        didSet {
            if duration != oldValue {
                visible = ScrubberWindow(duration: duration)
                needsLayout = true
            }
        }
    }

    var waveform: JGWaveformPeaks? {
        didSet {
            if waveform != oldValue {
                waveformChanged = true
                needsLayout = true
            }
            if (waveform == nil) != (oldValue == nil) {
                needsDisplay = true
            }
        }
    }

    var detail: JGWaveformDetail? {
        didSet {
            if detail != oldValue, visible.isZoomed {
                needsLayout = true
            }
        }
    }

    /// Ignored while the user drags (the drag position wins).
    var time: Double = 0 {
        didSet {
            motion.report(time)
            if !isScrubbing {
                followPlayhead(from: oldValue)
                placePlayhead()
            }
        }
    }

    var segment: ClosedRange<Double>? {
        didSet {
            if segment != oldValue {
                placeSegment()
            }
        }
    }

    var allowsZoom = false {
        didSet {
            if !allowsZoom, visible.isZoomed {
                visible = ScrubberWindow(duration: duration)
                windowDidChange()
            }
        }
    }

    var onSeek: ((Double, Bool) -> Void)?
    /// Speed while playing, 0 paused (`JGLiveTime.rate`).
    var playbackRate: Double = 0 {
        didSet { updateMotion() }
    }

    let motion = PlayheadMotion()
    var wheelZooms = false
    /// The waveform's share of the height (the narrow style: ½).
    var waveformHeight: CGFloat = 1 {
        didSet {
            if waveformHeight != oldValue {
                needsLayout = true
            }
        }
    }

    /// Waveform changes morph in (off with Reduce Motion).
    var animatesWaveform = false
    let morph = WaveformMorph()
    var waveformChanged = false
    var animatesPlayhead = true {
        didSet { updateMotion() }
    }

    var onSegmentChange: ((ClosedRange<Double>, JGSegmentEdge, Bool) -> Void)?
    var onWindowChange: ((ClosedRange<Double>) -> Void)?
    var segmentMenu: (() -> NSMenu?)?
    /// The shown part of the timeline.
    var visible = ScrubberWindow(duration: 0)
    var isScrubbing = false
    var scrubTime: Double = 0
    /// The segment end being dragged.
    var draggedEdge: JGSegmentEdge?

    let trackLayer = CAShapeLayer()
    let playedLayer = CAShapeLayer()
    private let playedMask = CALayer()
    private let playheadLayer = CALayer()
    private let segmentTint = CALayer()
    private let bracketsLayer = CAShapeLayer()
    /// Dims the timeline outside the segment (what will not be exported).
    private let outsideLayer = CAShapeLayer()
    /// Clip the tint and the brackets to the bounds (zoomed in, segment ends may lie outside).
    private let tintClip = CALayer()
    private let bracketsClip = CALayer()

    /// Seconds moved by VoiceOver increment / decrement.
    static let accessibilityStep = 5.0
    /// The shortest segment, in seconds.
    static let minimumSegment = 0.1

    override public init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        for sublayer in [tintClip, trackLayer, playedLayer, bracketsClip, playheadLayer] {
            layer?.addSublayer(sublayer)
        }
        tintClip.addSublayer(segmentTint)
        bracketsClip.addSublayer(outsideLayer)
        bracketsClip.addSublayer(bracketsLayer)
        outsideLayer.isHidden = true
        tintClip.masksToBounds = true
        bracketsClip.masksToBounds = true
        playedLayer.mask = playedMask
        playedMask.backgroundColor = CGColor(gray: 0, alpha: 1)
        segmentTint.isHidden = true
        bracketsLayer.isHidden = true
        for layer in [trackLayer, playedLayer, playedMask, playheadLayer, segmentTint, bracketsLayer, tintClip, bracketsClip,
                      outsideLayer]
        {
            layer.actions = ["position": NSNull(), "bounds": NSNull(), "path": NSNull(), "frame": NSNull(), "hidden": NSNull()]
        }
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override public var isFlipped: Bool {
        true
    }

    override public var wantsUpdateLayer: Bool {
        true
    }

    override public var mouseDownCanMoveWindow: Bool {
        false
    }

    override public func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    // MARK: Layout and colors

    override public func layout() {
        super.layout()
        let shown = visible.isZoomed ? visible : nil
        for layer in [trackLayer, playedLayer, tintClip, bracketsClip] {
            layer.frame = bounds
        }
        if let waveform {
            layoutWaveform(waveform, shown: shown)
        } else {
            morph.jump(to: WaveColumns(tops: [], bottoms: []))
            trackLayer.path = Self.sliderPath(width: bounds.width, in: bounds)
        }
        placePlayhead()
        placeSegment()
    }

    override public func updateLayer() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            // A waveform's unplayed part: the light text at 35 % (D-79); a plain track: the slider's.
            trackLayer.fillColor = waveform == nil
                ? JGColor.lineStrong.nsColor.cgColor
                : JGColor.textPrimary.nsColor.withAlphaComponent(JGMetrics.waveformUnplayedOpacity).cgColor
            playedLayer.fillColor = JGColor.textPrimary.nsColor.cgColor
            playheadLayer.backgroundColor = JGColor.textPrimary.nsColor.cgColor
            bracketsLayer.fillColor = JGColor.accent.nsColor.cgColor
            outsideLayer.fillColor = JGColor.bgMedia.nsColor.withAlphaComponent(JGMetrics.segmentOutsideOpacity).cgColor
            segmentTint.backgroundColor = JGColor.accent.nsColor.withAlphaComponent(JGMetrics.segmentTintOpacity).cgColor
        }
    }

    /// The x of `time` on screen (a playhead-wide strip is kept inside the bounds at both ends).
    func x(of time: Double) -> CGFloat {
        visible.x(of: time, width: bounds.width - JGMetrics.selectionEdgeWidth)
    }

    func placePlayhead() {
        let shown = isScrubbing ? scrubTime : motion.time
        let width = JGMetrics.selectionEdgeWidth
        let x = duration > 0 ? x(of: min(max(shown, 0), duration)) : 0
        // A plain track shows the position by its fill alone (W-99); a waveform has a thin playhead.
        playheadLayer.isHidden = waveform == nil || x < -width || x > bounds.width
        playheadLayer.frame = CGRect(x: x, y: 0, width: width, height: bounds.height)
        let filled = min(max(x + width / 2, 0), bounds.width)
        if waveform == nil {
            playedMask.frame = bounds
            playedLayer.path = duration > 0 && filled > 0 ? Self.sliderPath(width: filled, in: bounds) : nil
        } else {
            playedMask.frame = CGRect(x: 0, y: 0, width: filled, height: bounds.height)
        }
    }

    /// The brackets: `[` at the start, `]` at the end, a faint accent between.
    func placeSegment() {
        guard let segment, duration > 0 else {
            segmentTint.isHidden = true
            bracketsLayer.isHidden = true
            outsideLayer.isHidden = true
            return
        }
        let width = JGMetrics.selectionEdgeWidth
        let serif = JGMetrics.segmentBracketSerif
        let height = bounds.height
        let startX = x(of: segment.lowerBound)
        let endX = x(of: segment.upperBound) + width
        let path = CGMutablePath()
        path.addRect(CGRect(x: startX, y: 0, width: width, height: height))
        path.addRect(CGRect(x: startX, y: 0, width: serif, height: width))
        path.addRect(CGRect(x: startX, y: height - width, width: serif, height: width))
        path.addRect(CGRect(x: endX - width, y: 0, width: width, height: height))
        path.addRect(CGRect(x: endX - serif, y: 0, width: serif, height: width))
        path.addRect(CGRect(x: endX - serif, y: height - width, width: serif, height: width))
        bracketsLayer.frame = bounds
        bracketsLayer.path = path
        bracketsLayer.isHidden = false
        segmentTint.frame = CGRect(x: startX, y: 0, width: max(endX - startX, 0), height: height)
        segmentTint.isHidden = false
        let outside = CGMutablePath()
        outside.addRect(CGRect(x: -width, y: 0, width: max(startX + width, 0), height: height))
        outside.addRect(CGRect(x: endX, y: 0, width: max(bounds.width - endX + width, 0), height: height))
        outsideLayer.frame = bounds
        outsideLayer.path = outside
        outsideLayer.isHidden = false
    }

    /// Zoomed in while playing: when the playhead runs past the right edge, the next page shows.
    func followPlayhead(from previous: Double, to now: Double? = nil) {
        let now = now ?? time
        guard visible.isZoomed, previous <= visible.end, now > visible.end, now - previous < visible.length else { return }
        visible.page(to: now)
        windowDidChange()
    }

    func windowDidChange() {
        needsLayout = true
        onWindowChange?(visible.range)
    }
}
