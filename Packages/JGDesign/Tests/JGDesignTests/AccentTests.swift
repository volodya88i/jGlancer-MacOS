import Testing
@testable import JGDesign

struct AccentTests {
    @Test func aChosenColorIsExactOnFillsAndMovesOnlyWhereItIsText() {
        let chosen = JGChosenAccent(color: 0x1F3BFF)
        #expect(chosen.value(of: "accent", isDark: true, isBlack: false) == JGRGB(hex: 0x1F3BFF))
        // Too dark to read on the dark surfaces: lighter, same hue. On light surfaces it already reads.
        let dark = JGAccent.text(0x1F3BFF, isDark: true)
        #expect(dark != 0x1F3BFF)
        #expect(JGRGB(hex: dark).contrastRatio(with: JGColor.bgBase.dark) >= 4.5)
        #expect(JGAccent.text(0x1F3BFF, isDark: false) == 0x1F3BFF)
        #expect(JGRGB(hex: JGAccent.textBlack(0x1F3BFF)).contrastRatio(with: JGRGB(hex: 0x000000)) >= 4.5)
        // A light yellow on light surfaces goes darker.
        #expect(JGRGB(hex: JGAccent.text(0xF5B800, isDark: false)).contrastRatio(with: JGColor.bgPanel.light) >= 4.5)
    }

    @Test func dimIsAQuietVersionOfTheHue() {
        #expect(JGRGB(hex: JGAccent.dim(0xE60012, isDark: true)).contrastRatio(with: JGColor.textPrimary.dark) >= 4.5)
        #expect(JGRGB(hex: JGAccent.dim(0xE60012, isDark: false)).contrastRatio(with: JGColor.textPrimary.light) >= 4.5)
    }

    @Test func whatSitsOnTheAccentReads() {
        #expect(JGAccent.on(0xA396F4) == 0x000000)
        #expect(JGAccent.on(0x7A2CFF) == 0xFFFFFF)
        #expect(JGAccent.presets.first?.color == JGAccent.defaultColor)
        #expect(!JGAccent.presets.contains { $0.color == 0x1F3BFF })
        // The default is exact in every theme (D-105), and what sits on it is what `on` picks.
        #expect(JGColor.accent.light == JGRGB(hex: JGAccent.defaultColor))
        #expect(JGColor.accent.dark == JGRGB(hex: JGAccent.defaultColor))
        #expect(JGColor.accentOn.light == JGRGB(hex: JGAccent.on(JGAccent.defaultColor)))
    }

    @Test func hexTextParsesAndFormats() {
        #expect(JGAccent.parse("#1f3bff") == 0x1F3BFF)
        #expect(JGAccent.parse(" 1F3BFF ") == 0x1F3BFF)
        #expect(JGAccent.parse("#12345") == nil)
        #expect(JGAccent.parse("nope") == nil)
        #expect(JGAccent.parse(nil) == nil)
        #expect(JGAccent.format(0x00A6C8) == "#00A6C8")
    }

    @Test func tokensHaveTheirBlackValues() {
        #expect(JGColor.bgPanel.black == JGRGB(hex: 0x000000))
        #expect(JGColor.bgRaised.black == JGRGB(hex: 0x1F1F1F))
        #expect(JGColor.textPrimary.black == nil)
        // Without a theme set, tokens give their own values.
        #expect(JGColor.bgPopup.ownValue(isDark: true, increasedContrast: false) == JGColor.bgRaised.dark)
    }
}
