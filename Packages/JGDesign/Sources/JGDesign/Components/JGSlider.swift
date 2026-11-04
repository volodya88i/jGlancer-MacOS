import AppKit
import SwiftUI

/// The plain slider (W-98, W-99): a 4 pt rounded track in `line.strong`, the part up to the value in `text.primary`, no
/// thumb. Used for the thumbnail size, the volume and an image sequence's frames.
///
/// Input: click or drag (any value), two-finger scroll over it (trackpad) or the mouse wheel (a fifth of a step per
/// notch); with ⇧ held, drags and scrolls snap to steps (D-77, W-69). ←/→ when focused move a step; no focus
/// ring is drawn. VoiceOver sees an adjustable slider. Implemented in AppKit because it sits in the window's title-bar
/// strip, where a SwiftUI drag would move the window instead.
public struct JGSlider: NSViewRepresentable {
    @Binding private var value: Double
    private let range: ClosedRange<Double>
    private let step: Double
    private let accessibilityLabel: String
    private let focusesOnClick: Bool

    /// - Parameters:
    ///   - step: the keyboard increment, and what ⇧ snaps to.
    ///   - accessibilityLabel: localized name read by VoiceOver.
    ///   - focusesOnClick: false keeps the keyboard where it was (a player's volume: arrows keep seeking).
    public init(
        value: Binding<Double>, in range: ClosedRange<Double>, step: Double, accessibilityLabel: String,
        focusesOnClick: Bool = true
    ) {
        _value = value
        self.range = range
        self.step = step
        self.accessibilityLabel = accessibilityLabel
        self.focusesOnClick = focusesOnClick
    }

    public func makeNSView(context _: Context) -> SliderView {
        SliderView()
    }

    public func updateNSView(_ view: SliderView, context _: Context) {
        view.range = range
        view.step = step
        view.value = value
        view.focusesOnClick = focusesOnClick
        view.setAccessibilityLabel(accessibilityLabel)
        view.onChange = { newValue in
            value = newValue
        }
    }

    public func sizeThatFits(_ proposal: ProposedViewSize, nsView _: SliderView, context _: Context) -> CGSize? {
        CGSize(width: proposal.width ?? JGMetrics.sidebarWidth / 2, height: JGMetrics.controlHeightCompact)
    }
}

/// The AppKit view behind `JGSlider`.
public final class SliderView: NSView {
    var range: ClosedRange<Double> = 0 ... 1 {
        didSet { needsDisplay = true }
    }

    var step = 1.0
    var value = 0.0 {
        didSet {
            if value != oldValue {
                needsDisplay = true
            }
        }
    }

    var onChange: ((Double) -> Void)?
    var focusesOnClick = true

    /// Finger travel, in points, that sweeps the whole range on a trackpad.
    private static let scrollTravel = 300.0
    /// A mouse-wheel notch moves this part of a tick.
    static let wheelFraction = 0.2
    /// ⇧-scrolling: travel not yet turned into a tick.
    private var pendingSnap = 0.0
    /// The window's own movability while a press holds it still.
    private var heldWindow: (window: NSWindow, wasMovable: Bool)?

    override public var isFlipped: Bool {
        true
    }

    /// Never let a drag here move the window (the control sits in the title-bar strip).
    override public var mouseDownCanMoveWindow: Bool {
        false
    }

    override public func acceptsFirstMouse(for _: NSEvent?) -> Bool {
        true
    }

    override public var acceptsFirstResponder: Bool {
        true
    }

    override public var focusRingType: NSFocusRingType {
        get { .none }
        set {}
    }

    override public var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: JGMetrics.controlHeightCompact)
    }

    // MARK: Input

    override public func mouseDown(with event: NSEvent) {
        if focusesOnClick {
            window?.makeFirstResponder(self)
        }
        // In the title-bar strip the window's own drag can still start under a SwiftUI host; the window stays still
        // until the press ends (D-112).
        if let window, heldWindow == nil {
            heldWindow = (window, window.isMovable)
            window.isMovable = false
        }
        track(event)
    }

    override public func mouseDragged(with event: NSEvent) {
        track(event)
    }

    override public func mouseUp(with _: NSEvent) {
        releaseWindow()
    }

    override public func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        releaseWindow()
    }

    private func releaseWindow() {
        if let held = heldWindow {
            held.window.isMovable = held.wasMovable
            heldWindow = nil
        }
    }

    private func track(_ event: NSEvent) {
        let x = convert(event.locationInWindow, from: nil).x
        let fraction = min(max(x / max(bounds.width, 1), 0), 1)
        let target = range.lowerBound + Double(fraction) * span
        set(event.modifierFlags.contains(.shift) ? snapped(target) : target)
    }

    /// The nearest tick.
    func snapped(_ target: Double) -> Double {
        guard step > 0 else { return target }
        return range.lowerBound + ((target - range.lowerBound) / step).rounded() * step
    }

    /// Two fingers up or right enlarge, down or left shrink, whatever the "natural scrolling" setting.
    override public func scrollWheel(with event: NSEvent) {
        let inverted = event.isDirectionInvertedFromDevice
        let fingersUp = inverted ? -event.scrollingDeltaY : event.scrollingDeltaY
        let fingersRight = inverted ? event.scrollingDeltaX : -event.scrollingDeltaX
        // A wheel turned with ⇧ arrives as horizontal scrolling of the same sign: wheels take the raw delta.
        let raw = abs(event.scrollingDeltaY) >= abs(event.scrollingDeltaX) ? event.scrollingDeltaY : event.scrollingDeltaX
        let wheel = inverted ? -raw : raw
        let delta = Double(event.hasPreciseScrollingDeltas ? (abs(fingersUp) >= abs(fingersRight) ? fingersUp : fingersRight) : wheel)
        guard delta != 0 else { return }
        let travel = event.hasPreciseScrollingDeltas ? delta * span / Self.scrollTravel : (delta > 0 ? 1 : -1) * step * Self.wheelFraction
        guard event.modifierFlags.contains(.shift) else {
            set(value + travel)
            return
        }
        // Snapping: a tick at a time, once the scrolled travel reaches half a tick.
        let base = snapped(value)
        if event.hasPreciseScrollingDeltas {
            pendingSnap += travel
            guard abs(pendingSnap) >= step / 2 else { return }
            set(base + (pendingSnap > 0 ? step : -step))
            pendingSnap = 0
        } else {
            set(base + (delta > 0 ? step : -step))
        }
    }

    override public func keyDown(with event: NSEvent) {
        interpretKeyEvents([event])
    }

    override public func moveLeft(_: Any?) {
        set(value - step)
    }

    override public func moveDown(_: Any?) {
        set(value - step)
    }

    override public func moveRight(_: Any?) {
        set(value + step)
    }

    override public func moveUp(_: Any?) {
        set(value + step)
    }

    private var span: Double {
        range.upperBound - range.lowerBound
    }

    private func set(_ newValue: Double) {
        let clamped = min(max(newValue.rounded(), range.lowerBound), range.upperBound)
        guard clamped != value else { return }
        value = clamped
        onChange?(clamped)
        NSAccessibility.post(element: self, notification: .valueChanged)
    }

    // MARK: Drawing

    override public func draw(_: NSRect) {
        let thickness = JGMetrics.sliderThickness
        let track = NSRect(x: 0, y: (bounds.height - thickness) / 2, width: bounds.width, height: thickness)
        JGColor.lineStrong.nsColor.setFill()
        NSBezierPath(roundedRect: track, xRadius: thickness / 2, yRadius: thickness / 2).fill()
        let fraction = span > 0 ? min(max((value - range.lowerBound) / span, 0), 1) : 0
        guard fraction > 0 else { return }
        var filled = track
        filled.size.width = max(CGFloat(fraction) * bounds.width, thickness)
        JGColor.textPrimary.nsColor.setFill()
        NSBezierPath(roundedRect: filled, xRadius: thickness / 2, yRadius: thickness / 2).fill()
    }

    // MARK: Accessibility

    override public func isAccessibilityElement() -> Bool {
        true
    }

    override public func accessibilityRole() -> NSAccessibility.Role? {
        .slider
    }

    override public func accessibilityValue() -> Any? {
        NSNumber(value: Int(value))
    }

    override public func accessibilityMinValue() -> Any? {
        NSNumber(value: Int(range.lowerBound))
    }

    override public func accessibilityMaxValue() -> Any? {
        NSNumber(value: Int(range.upperBound))
    }

    override public func accessibilityPerformIncrement() -> Bool {
        set(value + step)
        return true
    }

    override public func accessibilityPerformDecrement() -> Bool {
        set(value - step)
        return true
    }
}

#Preview {
    JGSlider(value: .constant(160), in: 80 ... 320, step: 20, accessibilityLabel: "Thumbnail size")
        .frame(width: 140)
        .padding(JGSpacing.l)
        .background(JGColor.bgBase)
}
