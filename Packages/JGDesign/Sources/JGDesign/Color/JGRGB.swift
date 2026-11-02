import Foundation

/// An sRGB color with gamma-encoded components in `0...1`, plus WCAG contrast math.
public struct JGRGB: Hashable, Sendable {
    public let red: Double
    public let green: Double
    public let blue: Double
    public let alpha: Double

    /// Creates a color from gamma-encoded sRGB components.
    public init(red: Double, green: Double, blue: Double, alpha: Double = 1) {
        self.red = red
        self.green = green
        self.blue = blue
        self.alpha = alpha
    }

    /// Creates a color from a `0xRRGGBB` literal.
    public init(hex: UInt32, alpha: Double = 1) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            alpha: alpha
        )
    }

    /// `#RRGGBB`, ignoring alpha.
    public var hexString: String {
        let components = [red, green, blue].map { Int(($0 * 255).rounded()) }
        return "#" + components.map { String(format: "%02X", $0) }.joined()
    }

    /// WCAG 2.x relative luminance of the color, ignoring alpha.
    public var relativeLuminance: Double {
        func linear(_ component: Double) -> Double {
            component <= 0.040_45 ? component / 12.92 : pow((component + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// WCAG 2.x contrast ratio between two opaque colors, from 1 to 21.
    public func contrastRatio(with other: JGRGB) -> Double {
        let lighter = max(relativeLuminance, other.relativeLuminance)
        let darker = min(relativeLuminance, other.relativeLuminance)
        return (lighter + 0.05) / (darker + 0.05)
    }

    /// This color painted with its alpha over an opaque `background` (gamma-space blending, like the compositor).
    public func composited(over background: JGRGB) -> JGRGB {
        func blend(_ top: Double, _ bottom: Double) -> Double {
            alpha * top + (1 - alpha) * bottom
        }
        return JGRGB(
            red: blend(red, background.red),
            green: blend(green, background.green),
            blue: blend(blue, background.blue)
        )
    }
}
