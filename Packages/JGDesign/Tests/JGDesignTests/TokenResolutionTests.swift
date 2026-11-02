import AppKit
import SwiftUI
import Testing
@testable import JGDesign

@MainActor
struct TokenResolutionTests {
    private func resolved(_ token: JGColorToken, in name: NSAppearance.Name) throws -> String {
        let appearance = try #require(NSAppearance(named: name))
        var hex = ""
        appearance.performAsCurrentDrawingAppearance {
            if let color = token.nsColor.usingColorSpace(.sRGB) {
                hex = JGRGB(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent).hexString
            }
        }
        return hex
    }

    @Test func nsColorFollowsAppearance() throws {
        let token = JGColor.lineHair
        #expect(try resolved(token, in: .darkAqua) == token.dark.hexString)
        #expect(try resolved(token, in: .aqua) == token.light.hexString)
    }

    /// High-contrast appearances cannot be instantiated in tests (AppKit only reports them
    /// when Increase Contrast is on), so the name-to-flags mapping is tested directly.
    @Test func increaseContrastAppearancesMapToIncreasedValues() {
        let darkHC = JGColorToken.appearanceFlags(forBestMatch: .accessibilityHighContrastDarkAqua)
        #expect(darkHC.isDark && darkHC.increasedContrast)
        let lightHC = JGColorToken.appearanceFlags(forBestMatch: .accessibilityHighContrastAqua)
        #expect(!lightHC.isDark && lightHC.increasedContrast)
        let dark = JGColorToken.appearanceFlags(forBestMatch: .darkAqua)
        #expect(dark.isDark && !dark.increasedContrast)
        let fallback = JGColorToken.appearanceFlags(forBestMatch: nil)
        #expect(!fallback.isDark && !fallback.increasedContrast)
    }

    @Test func shapeStyleResolvesFromEnvironment() {
        var environment = EnvironmentValues()
        environment.colorScheme = .dark
        let dark = JGColor.accentText.resolve(in: environment)
        environment.colorScheme = .light
        let light = JGColor.accentText.resolve(in: environment)
        #expect(abs(Double(dark.red) - Double(light.red)) > 0.01)
    }
}
