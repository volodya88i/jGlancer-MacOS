import AppKit
import JGModel

/// The size map's colors (D-127): a family per kind — photos blue, videos violet, audio amber — and within it a shade
/// per extension (JPG and HEIC tell apart), calm enough for the app's neutrals, lighter in the light theme.
struct SizeMapPalette: Sendable {
    struct RGB: Sendable {
        let red: Double
        let green: Double
        let blue: Double

        var cgColor: CGColor {
            CGColor(srgbRed: red, green: green, blue: blue, alpha: 1)
        }
    }

    let isDark: Bool
    let folderFill: RGB
    let headerFill: RGB
    let label: RGB
    let gap: RGB

    /// Hues of the kinds, in degrees.
    static func hue(_ kind: MediaKind) -> Double {
        switch kind {
        case .photo: 212
        case .video: 268
        case .audio: 34
        }
    }

    /// Shades per family.
    static let shades = 4

    func color(kind: MediaKind, fileExtension: String) -> RGB {
        // A stable shade for the extension (Swift's own hash changes between launches).
        let shade = Double(fileExtension.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) & 0xFFFF } % Self.shades)
        let lightness = isDark ? 0.40 + shade * 0.06 : 0.58 + shade * 0.06
        return Self.rgb(hue: Self.hue(kind), saturation: isDark ? 0.42 : 0.48, lightness: lightness)
    }

    static func rgb(hue: Double, saturation: Double, lightness: Double) -> RGB {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        let segment = hue / 60
        let second = chroma * (1 - abs(segment.truncatingRemainder(dividingBy: 2) - 1))
        let match = lightness - chroma / 2
        let high = chroma + match
        let middle = second + match
        return switch Int(segment) % 6 {
        case 0: RGB(red: high, green: middle, blue: match)
        case 1: RGB(red: middle, green: high, blue: match)
        case 2: RGB(red: match, green: high, blue: middle)
        case 3: RGB(red: match, green: middle, blue: high)
        case 4: RGB(red: middle, green: match, blue: high)
        default: RGB(red: high, green: match, blue: middle)
        }
    }
}
