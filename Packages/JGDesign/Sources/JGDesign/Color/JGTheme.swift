import os
import SwiftUI

/// What tokens resolve against besides the appearance: the Black theme (a variant of dark, W-97) and the accent the
/// user chose (W-93, W-98). Set by the app whenever the settings change; AppKit views then redraw on request and
/// SwiftUI through `jgThemeRevision`.
public struct JGTheme: Sendable {
    public var isBlack = false
    public var accent: JGChosenAccent?
    /// Grows with every change.
    public private(set) var revision = 0

    private static let state = OSAllocatedUnfairLock(initialState: JGTheme())

    /// The theme in force.
    public static var current: JGTheme {
        state.withLock { $0 }
    }

    /// Sets the theme; false when nothing changed.
    @discardableResult
    public static func set(isBlack: Bool, accent: UInt32?) -> Bool {
        // The default color is the tokens' own values.
        let chosen = accent == JGAccent.defaultColor ? nil : accent
        return state.withLock { theme in
            guard theme.isBlack != isBlack || theme.accent?.color != chosen else { return false }
            theme.isBlack = isBlack
            theme.accent = chosen.map { JGChosenAccent(color: $0) }
            theme.revision += 1
            return true
        }
    }
}

public extension EnvironmentValues {
    /// Changes with the theme, so SwiftUI resolves tokens again (root views set it from `JGTheme.current.revision`).
    @Entry var jgThemeRevision = 0
}

/// A chosen accent's values for the three accent tokens, computed once.
public struct JGChosenAccent: Equatable, Sendable {
    public let color: UInt32
    private let textDark: JGRGB
    private let textLight: JGRGB
    private let textBlack: JGRGB
    private let dimDark: JGRGB
    private let dimLight: JGRGB

    init(color: UInt32) {
        self.color = color
        textDark = JGRGB(hex: JGAccent.text(color, isDark: true))
        textLight = JGRGB(hex: JGAccent.text(color, isDark: false))
        textBlack = JGRGB(hex: JGAccent.textBlack(color))
        dimDark = JGRGB(hex: JGAccent.dim(color, isDark: true))
        dimLight = JGRGB(hex: JGAccent.dim(color, isDark: false))
    }

    func value(of token: String, isDark: Bool, isBlack: Bool) -> JGRGB? {
        switch token {
        case "accent": JGRGB(hex: color)
        case "accent.text": isDark ? (isBlack ? textBlack : textDark) : textLight
        case "accent.on": JGRGB(hex: JGAccent.on(color))
        case "accent.dim": isDark ? dimDark : dimLight
        default: nil
        }
    }
}

/// The accent the user chooses (W-93, W-98): one color, shown exactly in every theme on fills and edges. Where it is
/// text or a thin glyph (`accent.text`) only its lightness moves, by the smallest step that keeps it readable on that
/// theme's surfaces.
public enum JGAccent {
    /// The default accent (D-102): the tokens' own values, a deeper lavender on light themes.
    public static let defaultColor: UInt32 = 0xA396F4

    /// The colors offered in Settings, the default first.
    public static let presets: [(name: String, color: UInt32)] = [
        ("Lavender", defaultColor), ("Purple", 0x7A2CFF), ("Pink", 0xFF2E93), ("Red", 0xE60012),
        ("Orange", 0xFF4F1A), ("Yellow", 0xF5B800), ("Green", 0x18A558), ("Teal", 0x00A6C8),
    ]

    /// `#RRGGBB` for a color.
    public static func format(_ color: UInt32) -> String {
        String(format: "#%06X", color & 0xFFFFFF)
    }

    /// A color from `#RRGGBB` or `RRGGBB`; nil for anything else.
    public static func parse(_ text: String?) -> UInt32? {
        guard var hex = text?.trimmingCharacters(in: .whitespacesAndNewlines) else { return nil }
        if hex.hasPrefix("#") {
            hex.removeFirst()
        }
        guard hex.count == 6, hex.allSatisfy(\.isHexDigit) else { return nil }
        return UInt32(hex, radix: 16)
    }

    /// White or black, whichever reads better on `accent` (a tick, a switch's knob).
    public static func on(_ accent: UInt32) -> UInt32 {
        let rgb = JGRGB(hex: accent)
        return rgb.contrastRatio(with: JGRGB(hex: 0xFFFFFF)) >= rgb.contrastRatio(with: JGRGB(hex: 0x000000)) ? 0xFFFFFF : 0x000000
    }

    /// The `accent.text` value of `chosen` in one appearance.
    public static func text(_ chosen: UInt32, isDark: Bool) -> UInt32 {
        adjusted(chosen, lighter: isDark) { $0.ownValue(isDark: isDark, increasedContrast: false) }
    }

    /// The `accent.text` value of `chosen` in the Black theme.
    public static func textBlack(_ chosen: UInt32) -> UInt32 {
        adjusted(chosen, lighter: true) { $0.black ?? $0.dark }
    }

    /// The `accent.dim` value (selection fill) of `chosen` in one appearance.
    public static func dim(_ chosen: UInt32, isDark: Bool) -> UInt32 {
        let color = hsl(chosen)
        return isDark ? fromHSL(color.hue, min(color.saturation, 0.45), 0.22) : fromHSL(color.hue, min(color.saturation, 0.75), 0.92)
    }

    private static func adjusted(_ chosen: UInt32, lighter: Bool, surface: (JGColorToken) -> JGRGB) -> UInt32 {
        if meetsContrast(chosen, surface) {
            return chosen
        }
        let color = hsl(chosen)
        let step = lighter ? 0.01 : -0.01
        var lightness = color.lightness + step
        while lightness > 0, lightness < 1 {
            let moved = fromHSL(color.hue, color.saturation, lightness)
            if meetsContrast(moved, surface) {
                return moved
            }
            lightness += step
        }
        return lighter ? 0xFFFFFF : 0x000000
    }

    /// Text on the base and panel surfaces, graphics on every surface.
    private static func meetsContrast(_ color: UInt32, _ surface: (JGColorToken) -> JGRGB) -> Bool {
        let rgb = JGRGB(hex: color)
        return rgb.contrastRatio(with: surface(JGColor.bgBase)) >= 4.5
            && rgb.contrastRatio(with: surface(JGColor.bgPanel)) >= 4.5
            && rgb.contrastRatio(with: surface(JGColor.bgRaised)) >= 3
            && rgb.contrastRatio(with: surface(JGColor.bgMedia)) >= 3
    }

    private struct HSL {
        let hue: Double
        let saturation: Double
        let lightness: Double
    }

    private static func hsl(_ color: UInt32) -> HSL {
        let red = Double((color >> 16) & 0xFF) / 255
        let green = Double((color >> 8) & 0xFF) / 255
        let blue = Double(color & 0xFF) / 255
        let top = max(red, green, blue)
        let bottom = min(red, green, blue)
        let lightness = (top + bottom) / 2
        let chroma = top - bottom
        guard chroma > 0 else { return HSL(hue: 0, saturation: 0, lightness: lightness) }
        let saturation = chroma / (1 - abs(2 * lightness - 1))
        let sector = top == red ? (green - blue) / chroma : top == green ? (blue - red) / chroma + 2 : (red - green) / chroma + 4
        return HSL(hue: (sector + 6).truncatingRemainder(dividingBy: 6) / 6, saturation: saturation, lightness: lightness)
    }

    private static func fromHSL(_ hue: Double, _ saturation: Double, _ lightness: Double) -> UInt32 {
        let chroma = (1 - abs(2 * lightness - 1)) * saturation
        func channel(_ offset: Double) -> UInt32 {
            let sector = (offset + hue * 12).truncatingRemainder(dividingBy: 12)
            let value = lightness - chroma / 2 * max(-1, min(sector - 3, 9 - sector, 1))
            return UInt32(min(max((value * 255).rounded(), 0), 255))
        }
        return channel(0) << 16 | channel(8) << 8 | channel(4)
    }
}
