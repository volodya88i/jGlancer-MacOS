import SwiftUI

/// Text with one accent-colored word, like the reference headline (docs/DESIGN.md §1).
///
/// The accent word is marked with Markdown strong emphasis inside the localized string,
/// e.g. `"Every frame. One **glance**."`, so each translation chooses its own accent word
/// and the sentence is never concatenated from pieces.
public struct JGAccentText: View {
    private let source: AttributedString
    @Environment(\.self) private var environment

    /// Creates accent text from a localized resource containing `**…**` around the accent word.
    public init(_ resource: LocalizedStringResource) {
        source = AttributedString(localized: resource)
    }

    /// Creates accent text from an already-parsed attributed string.
    public init(attributed: AttributedString) {
        source = attributed
    }

    public var body: some View {
        Text(Self.accented(source, accent: Color(JGColor.accentText.resolve(in: environment))))
    }

    /// Replaces strong emphasis with the accent color. Pure, so callable from any isolation.
    nonisolated static func accented(_ source: AttributedString, accent: Color) -> AttributedString {
        var result = source
        for range in accentRanges(in: source) {
            result[range].inlinePresentationIntent = nil
            result[range].foregroundColor = accent
        }
        return result
    }

    /// Ranges marked with strong emphasis.
    nonisolated static func accentRanges(in source: AttributedString) -> [Range<AttributedString.Index>] {
        source.runs
            .filter { $0.inlinePresentationIntent?.contains(.stronglyEmphasized) == true }
            .map(\.range)
    }
}

#Preview {
    JGAccentText(attributed: (try? AttributedString(markdown: "Every frame. One **glance**.")) ?? "")
        .jgTextStyle(.display)
        .foregroundStyle(JGColor.textPrimary)
        .padding(JGSpacing.xl)
        .background(JGColor.bgBase)
}
