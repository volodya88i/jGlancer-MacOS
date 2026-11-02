import AppKit

/// VoiceOver: an adjustable slider of the time.
public extension ScrubberView {
    override func isAccessibilityElement() -> Bool {
        true
    }

    override func accessibilityRole() -> NSAccessibility.Role? {
        .slider
    }

    override func accessibilityValue() -> Any? {
        NSNumber(value: Int(time))
    }

    override func accessibilityMinValue() -> Any? {
        NSNumber(value: 0)
    }

    override func accessibilityMaxValue() -> Any? {
        NSNumber(value: Int(duration))
    }

    override func accessibilityPerformIncrement() -> Bool {
        onSeek?(min(time + Self.accessibilityStep, duration), true)
        return true
    }

    override func accessibilityPerformDecrement() -> Bool {
        onSeek?(max(time - Self.accessibilityStep, 0), true)
        return true
    }
}
