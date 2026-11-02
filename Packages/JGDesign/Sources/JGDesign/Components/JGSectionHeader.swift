import SwiftUI

/// A small uppercase section label such as `LIBRARY` (docs/DESIGN.md §6).
///
/// VoiceOver reads it as a header.
public struct JGSectionHeader: View {
    private let title: Text

    /// Creates a header. Pass a localized `Text`; it is uppercased at display time.
    public init(_ title: Text) {
        self.title = title
    }

    public var body: some View {
        title
            .jgTextStyle(.label)
            .foregroundStyle(JGColor.textTertiary)
            .accessibilityAddTraits(.isHeader)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: JGSpacing.m) {
        JGSectionHeader(Text(verbatim: "Folders"))
        JGSectionHeader(Text(verbatim: "Albums"))
    }
    .padding(JGSpacing.l)
    .background(JGColor.bgBase)
}
