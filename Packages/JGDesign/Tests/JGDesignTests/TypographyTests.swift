import Testing
@testable import JGDesign

struct TypographyTests {
    @Test func noStyleIsSmallerThanTheMinimum() {
        for style in JGTextStyle.allCases {
            #expect(style.size >= JGTextStyle.minimumSize, "\(style) is \(style.size) pt")
        }
    }

    @Test func onlyLabelsAreUppercaseAndWidelyTracked() {
        #expect(JGTextStyle.allCases.filter(\.isUppercase) == [.label])
        #expect(JGTextStyle.label.tracking > 0)
        #expect(JGTextStyle.display.tracking < 0)
    }

    @Test func hairlineIsOneDevicePixel() {
        #expect(JGMetrics.hairline(displayScale: 2) == 0.5)
        #expect(JGMetrics.hairline(displayScale: 1) == 1)
        #expect(JGMetrics.hairline(displayScale: 0) == 1)
    }

    @Test func spacingIsOnTheFourPointGrid() {
        #expect(JGSpacing.scale == JGSpacing.scale.sorted())
        #expect(JGSpacing.scale.allSatisfy { $0.truncatingRemainder(dividingBy: 4) == 0 })
    }
}
