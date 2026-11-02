import Testing
@testable import JGDesign

struct ContrastTests {
    static let appearances: [(isDark: Bool, increasedContrast: Bool)] = [
        (true, false), (true, true), (false, false), (false, true),
    ]

    @Test(arguments: appearances.indices)
    func everyRequiredPairMeetsWCAG(appearanceIndex: Int) {
        let (isDark, increased) = Self.appearances[appearanceIndex]
        for requirement in JGContrastRequirements.all where !requirement.increasedContrastOnly || increased {
            let ratio = requirement.ratio(isDark: isDark, increasedContrast: increased)
            #expect(
                ratio >= requirement.minimumRatio,
                """
                \(requirement.foreground.name) on \(requirement.background.name) \
                (dark: \(isDark), increased: \(increased)) = \(ratio)
                """
            )
        }
    }

    @Test(arguments: [true, false])
    func primaryTextStaysReadableOnScrimOverAnyMedia(isDark: Bool) {
        let scrim = JGColor.overlayScrim.value(isDark: isDark, increasedContrast: false)
        let text = JGColor.textPrimary.value(isDark: isDark, increasedContrast: false)
        for media in [JGRGB(hex: 0xFFFFFF), JGRGB(hex: 0x000000), JGRGB(hex: 0x808080)] {
            #expect(text.contrastRatio(with: scrim.composited(over: media)) >= 4.5)
        }
    }

    @Test func tokenNamesAreUnique() {
        let names = JGColor.all.map(\.name)
        #expect(Set(names).count == names.count)
        #expect(names.count == 24)
    }

    @Test(arguments: [true, false])
    func flagStarsStayVisibleOnTheirBadgeOverAnyMedia(isDark: Bool) {
        let base = JGColor.bgBase.value(isDark: isDark, increasedContrast: false)
        let scrim = JGRGB(red: base.red, green: base.green, blue: base.blue, alpha: JGMetrics.flagBadgeOpacity)
        let flags = [
            JGColor.flagRed,
            JGColor.flagOrange,
            JGColor.flagYellow,
            JGColor.flagGreen,
            JGColor.flagBlue,
            JGColor.flagPurple,
            JGColor.accentText,
        ]
        for flag in flags {
            let color = flag.value(isDark: isDark, increasedContrast: false)
            for media in [JGRGB(hex: 0xFFFFFF), JGRGB(hex: 0x000000), JGRGB(hex: 0x808080)] {
                #expect(color.contrastRatio(with: scrim.composited(over: media)) >= 3, Comment(rawValue: flag.name))
            }
        }
    }

    @Test func contrastMathMatchesWCAGReferenceValues() {
        let white = JGRGB(hex: 0xFFFFFF)
        let black = JGRGB(hex: 0x000000)
        #expect(abs(white.contrastRatio(with: black) - 21) < 0.001)
        #expect(abs(white.contrastRatio(with: white) - 1) < 0.001)
        // #767676 on white is the classic 4.54:1 boundary color.
        #expect(abs(JGRGB(hex: 0x767676).contrastRatio(with: white) - 4.54) < 0.01)
    }

    @Test func hexRoundTrips() {
        #expect(JGRGB(hex: 0x7B9CF0).hexString == "#7B9CF0")
        #expect(JGRGB(hex: 0x101115, alpha: 0.72).composited(over: JGRGB(hex: 0x101115)).hexString == "#101115")
    }
}
