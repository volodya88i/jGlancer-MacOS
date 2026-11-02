import Foundation
import SwiftUI
import Testing
@testable import JGDesign

struct AccentTextTests {
    @Test func strongEmphasisMarksTheAccentWord() throws {
        let source = try AttributedString(markdown: "Every frame. One **glance**.")
        let ranges = JGAccentText.accentRanges(in: source)
        #expect(ranges.count == 1)
        #expect(ranges.first.map { String(source[$0].characters) } == "glance")
    }

    @Test func accentingRemovesEmphasisAndKeepsText() throws {
        let source = try AttributedString(markdown: "Каждый кадр. Один **взгляд**.")
        let result = JGAccentText.accented(source, accent: .blue)
        #expect(String(result.characters) == "Каждый кадр. Один взгляд.")
        #expect(JGAccentText.accentRanges(in: result).isEmpty)
    }

    @Test func localizedResourcesParseMarkdown() {
        // A key missing from every catalog falls back to itself; Markdown must still be parsed.
        let source = AttributedString(localized: LocalizedStringResource("Missing key with **accent**."))
        #expect(JGAccentText.accentRanges(in: source).count == 1)
    }
}
