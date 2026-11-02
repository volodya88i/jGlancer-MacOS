import AppKit
import SwiftUI

/// A semantic color with values for dark and light appearance, and optional
/// overrides for the system "Increase Contrast" setting.
///
/// Use it directly as a SwiftUI `ShapeStyle` (`.foregroundStyle(JGColor.textPrimary)`);
/// it resolves against the environment's color scheme and contrast. AppKit code uses `nsColor`.
public struct JGColorToken: ShapeStyle, Hashable, Sendable {
    /// The token's name as written in docs/DESIGN.md, e.g. `"bg.base"`.
    public let name: String
    public let dark: JGRGB
    public let light: JGRGB
    public let darkIncreasedContrast: JGRGB
    public let lightIncreasedContrast: JGRGB
    /// The Black theme's value (W-97); nil takes the dark one.
    public let black: JGRGB?

    /// Creates a token from `0xRRGGBB` literals. Increased-contrast values default to the normal ones.
    public init(
        _ name: String,
        dark: UInt32,
        light: UInt32,
        darkIncreasedContrast: UInt32? = nil,
        lightIncreasedContrast: UInt32? = nil,
        black: UInt32? = nil,
        alpha: Double = 1
    ) {
        self.name = name
        self.dark = JGRGB(hex: dark, alpha: alpha)
        self.light = JGRGB(hex: light, alpha: alpha)
        self.darkIncreasedContrast = JGRGB(hex: darkIncreasedContrast ?? dark, alpha: alpha)
        self.lightIncreasedContrast = JGRGB(hex: lightIncreasedContrast ?? light, alpha: alpha)
        self.black = black.map { JGRGB(hex: $0, alpha: alpha) }
    }

    /// The value for a given appearance in the current theme (`JGTheme`: Black, the chosen accent).
    public func value(isDark: Bool, increasedContrast: Bool) -> JGRGB {
        let theme = JGTheme.current
        if let chosen = theme.accent?.value(of: name, isDark: isDark, isBlack: theme.isBlack) {
            return chosen
        }
        if isDark, theme.isBlack, let black, !increasedContrast || darkIncreasedContrast == dark {
            return black
        }
        return ownValue(isDark: isDark, increasedContrast: increasedContrast)
    }

    /// The value as declared, whatever the theme.
    func ownValue(isDark: Bool, increasedContrast: Bool) -> JGRGB {
        switch (isDark, increasedContrast) {
        case (true, false): dark
        case (true, true): darkIncreasedContrast
        case (false, false): light
        case (false, true): lightIncreasedContrast
        }
    }

    public func resolve(in environment: EnvironmentValues) -> Color.Resolved {
        // Reading it makes SwiftUI resolve the token again when the theme changes.
        _ = environment.jgThemeRevision
        let rgb = value(
            isDark: environment.colorScheme == .dark,
            increasedContrast: environment.colorSchemeContrast == .increased
        )
        return Color.Resolved(
            colorSpace: .sRGB,
            red: Float(rgb.red),
            green: Float(rgb.green),
            blue: Float(rgb.blue),
            opacity: Float(rgb.alpha)
        )
    }

    /// A dynamic `NSColor` that follows the drawing appearance, including Increase Contrast.
    public var nsColor: NSColor {
        let token = self
        return NSColor(name: NSColor.Name(name)) { appearance in
            let flags = Self.appearanceFlags(forBestMatch: appearance.bestMatch(from: Self.appearanceCandidates))
            let rgb = token.value(isDark: flags.isDark, increasedContrast: flags.increasedContrast)
            return NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: rgb.alpha)
        }
    }

    /// Appearances a token distinguishes. High-contrast variants are reported by AppKit
    /// only when the user turns on Increase Contrast.
    static let appearanceCandidates: [NSAppearance.Name] = [
        .aqua, .darkAqua, .accessibilityHighContrastAqua, .accessibilityHighContrastDarkAqua,
    ]

    /// Maps the best-matching appearance name to the token's lookup flags.
    static func appearanceFlags(forBestMatch match: NSAppearance.Name?) -> (isDark: Bool, increasedContrast: Bool) {
        (
            isDark: match == .darkAqua || match == .accessibilityHighContrastDarkAqua,
            increasedContrast: match == .accessibilityHighContrastAqua || match == .accessibilityHighContrastDarkAqua
        )
    }
}
