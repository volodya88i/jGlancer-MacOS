import AppKit
import AVFoundation
import JGDesign
import JGModel
import SwiftUI

/// The video picture (an `AVPlayerLayer`, aspect-fit on `bg.media`) and the keyboard of the video and audio
/// viewers: Space, ←/→ seek, ⌥←/⌥→ previous/next, ↑/↓ volume, `,` `.` frame step, `[` `]` `\` speed
/// (docs/FEATURES.md §15). A click on a video plays or pauses it (released within `clickSlop` of the press);
/// a double-click undoes that and toggles full screen (D-110). With `onSwipe` (audio), mouse drags and two-finger
/// trackpad swipes page between files; mouse wheels do not.
final class MediaSurfaceView: NSView {
    var onCommand: ((MediaCommand) -> Void)?
    var onSwipe: ((SwipeInput) -> Void)?
    private var isDragging = false
    /// Where a single click on the video went down.
    private var pressLocation: NSPoint?
    var onActivity: (() -> Void)?
    var onContextMenu: (() -> NSMenu?)?
    /// False in previews: the library keeps the keyboard.
    var takesKeyboardFocus = true
    /// The full player's video zooms (wheel, pinch) and pans (drag, two-finger scroll) — D-80.
    var allowsZoom = false
    private var zoom = VideoZoom() {
        didSet {
            if zoom != oldValue {
                needsLayout = true
            }
        }
    }

    /// A new value (another file) returns to fit.
    var zoomResetID: AnyHashable? {
        didSet {
            if zoomResetID != oldValue {
                zoom.reset()
            }
        }
    }

    private var hasVideo: Bool {
        player != nil || sampleLayer != nil
    }

    private var zooms: Bool {
        allowsZoom && hasVideo
    }

    /// The player whose video is shown; nil for audio (the view then only takes keys).
    var player: AVPlayer? {
        didSet {
            guard player !== oldValue else { return }
            playerLayer.player = player
            playerLayer.isHidden = player == nil
        }
    }

    private let playerLayer = AVPlayerLayer()

    /// The picture of a Matroska file (its own layer, D-71), shown instead of the player's.
    var sampleLayer: AVSampleBufferDisplayLayer? {
        didSet {
            guard sampleLayer !== oldValue else { return }
            oldValue?.removeFromSuperlayer()
            if let sampleLayer {
                sampleLayer.frame = bounds
                layer?.addSublayer(sampleLayer)
            }
        }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        playerLayer.videoGravity = .resizeAspect
        playerLayer.actions = ["bounds": NSNull(), "position": NSNull()]
        playerLayer.isHidden = true
        layer?.addSublayer(playerLayer)
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateLayer() {}

    override func layout() {
        super.layout()
        zoom.clamp(in: bounds)
        let frame = zooms ? zoom.frame(in: bounds) : bounds
        playerLayer.frame = frame
        sampleLayer?.frame = frame
    }

    override var acceptsFirstResponder: Bool {
        takesKeyboardFocus
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if takesKeyboardFocus {
            window?.makeFirstResponder(self)
        }
        watchSpace()
    }

    /// Space plays and pauses wherever the keyboard focus is in the player's window (a menu button, a slider, the
    /// window itself), not only on the picture (WIN-061); a field being typed in keeps its spaces.
    private var spaceMonitor: Any?

    private func watchSpace() {
        if let spaceMonitor {
            NSEvent.removeMonitor(spaceMonitor)
        }
        spaceMonitor = nil
        guard takesKeyboardFocus, window != nil else { return }
        spaceMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window, event.window === window, event.keyCode == 49,
                  event.modifierFlags.isDisjoint(with: [.command, .control, .option, .shift]),
                  window.firstResponder !== self, !(window.firstResponder is NSText)
            else { return event }
            onActivity?()
            onCommand?(.togglePlay)
            return nil
        }
    }

    override func mouseDown(with event: NSEvent) {
        if takesKeyboardFocus {
            window?.makeFirstResponder(self)
        }
        onActivity?()
        isDragging = false
        pressLocation = event.clickCount == 1 && hasVideo ? event.locationInWindow : nil
        if event.clickCount == 2 {
            if hasVideo {
                onCommand?(.togglePlay)
            }
            onCommand?(.toggleFullScreen)
        }
    }

    override func mouseDragged(with event: NSEvent) {
        if zooms, !zoom.isFit {
            zoom.pan(by: CGVector(dx: event.deltaX, dy: -event.deltaY), in: bounds)
            return
        }
        guard let onSwipe else { return }
        if !isDragging {
            isDragging = true
            onSwipe(.began)
        }
        onSwipe(.moved(delta: event.deltaX, time: event.timestamp))
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            isDragging = false
            onSwipe?(.ended)
        }
        if let press = pressLocation, hypot(event.locationInWindow.x - press.x, event.locationInWindow.y - press.y) <= JGMetrics.clickSlop {
            onCommand?(.togglePlay)
        }
        pressLocation = nil
    }

    override func scrollWheel(with event: NSEvent) {
        if zooms, zoomOrPan(event) {
            return
        }
        // Trackpad swipes only (precise deltas); the momentum after the fingers lift is ignored.
        guard let onSwipe, event.hasPreciseScrollingDeltas else {
            super.scrollWheel(with: event)
            return
        }
        onActivity?()
        guard event.momentumPhase.isEmpty else { return }
        switch event.phase {
        case .began:
            onSwipe(.began)
            onSwipe(.moved(delta: SwipeInput.contentDelta(of: event), time: event.timestamp))
        case .changed:
            onSwipe(.moved(delta: SwipeInput.contentDelta(of: event), time: event.timestamp))
        case .ended, .cancelled:
            onSwipe(.ended)
        default:
            break
        }
    }

    /// A wheel zooms around the pointer; a two-finger scroll pans a zoomed picture. False when the event is a swipe.
    private func zoomOrPan(_ event: NSEvent) -> Bool {
        onActivity?()
        if !event.hasPreciseScrollingDeltas {
            let upward = event.isDirectionInvertedFromDevice ? -event.scrollingDeltaY : event.scrollingDeltaY
            zoom.zoom(by: exp(upward * MediaSurfaceView.wheelZoom), at: convert(event.locationInWindow, from: nil), in: bounds)
            return true
        }
        guard !zoom.isFit else { return false }
        zoom.pan(by: CGVector(dx: event.scrollingDeltaX, dy: -event.scrollingDeltaY), in: bounds)
        return true
    }

    /// Zoom per wheel line (e^(lines × this)).
    static let wheelZoom: CGFloat = 0.1

    override func magnify(with event: NSEvent) {
        guard zooms else {
            super.magnify(with: event)
            return
        }
        zoom.zoom(by: 1 + event.magnification, at: convert(event.locationInWindow, from: nil), in: bounds)
    }

    /// ⌘0 returns a zoomed picture to fit.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if zooms, !zoom.isFit, modifiers == .command, event.charactersIgnoringModifiers == "0" {
            zoom.reset()
            return true
        }
        return super.performKeyEquivalent(with: event)
    }

    override func menu(for _: NSEvent) -> NSMenu? {
        onContextMenu?()
    }

    override func keyDown(with event: NSEvent) {
        onActivity?()
        if let command = Self.command(for: event) {
            onCommand?(command)
        } else {
            super.keyDown(with: event)
        }
    }

    /// The command of a key press; nil for keys with ⌘ or ⌃ (menu shortcuts) and unknown keys.
    static func command(for event: NSEvent) -> MediaCommand? {
        let modifiers = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        guard modifiers.isDisjoint(with: [.command, .control]) else { return nil }
        if let special = event.specialKey {
            return arrowCommand(special, option: modifiers.contains(.option))
        }
        return event.charactersIgnoringModifiers.flatMap { characterCommands[$0] }
    }

    private static func arrowCommand(_ key: NSEvent.SpecialKey, option: Bool) -> MediaCommand? {
        switch key {
        case .leftArrow: option ? .previous : .seek(-MediaViewerModel.seekStep)
        case .rightArrow: option ? .next : .seek(MediaViewerModel.seekStep)
        case .upArrow: .volume(1)
        case .downArrow: .volume(-1)
        default: nil
        }
    }

    private static let characterCommands: [String: MediaCommand] = [
        " ": .togglePlay, ",": .step(-1), ".": .step(1), "[": .speed(-1), "]": .speed(1), "\\": .resetSpeed,
        "s": .toggleSegment, "m": .toggleMute, "p": .saveFrame, "P": .copyFrame,
    ]
}

/// SwiftUI host of `MediaSurfaceView`.
struct MediaSurface: NSViewRepresentable {
    let player: AVPlayer?
    /// A Matroska file's picture (`PlaybackController.matroskaLayer`).
    var sampleLayer: AVSampleBufferDisplayLayer?
    let accessibilityLabel: String
    var takesKeyboardFocus = true
    let onCommand: (MediaCommand) -> Void
    let onActivity: () -> Void
    var contextMenu: () -> NSMenu? = { nil }
    var onSwipe: ((SwipeInput) -> Void)?
    var allowsZoom = false
    var zoomResetID: AnyHashable?

    func makeNSView(context _: Context) -> MediaSurfaceView {
        let view = MediaSurfaceView(frame: .zero)
        view.takesKeyboardFocus = takesKeyboardFocus
        return view
    }

    func updateNSView(_ view: MediaSurfaceView, context _: Context) {
        view.player = player
        view.sampleLayer = sampleLayer
        view.onCommand = onCommand
        view.onActivity = onActivity
        view.onContextMenu = contextMenu
        view.onSwipe = onSwipe
        view.allowsZoom = allowsZoom
        view.zoomResetID = zoomResetID
        view.setAccessibilityLabel(accessibilityLabel)
    }
}
