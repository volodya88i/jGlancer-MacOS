import SwiftUI

/// A calm empty state (docs/DESIGN.md §8): a small label, one short headline (optional accent word),
/// one line of text and the actions. Nothing else.
public struct JGEmptyState<Actions: View>: View {
    private let label: Text?
    private let title: AttributedString
    private let message: Text?
    private let isLarge: Bool
    private let actions: Actions

    /// - Parameters:
    ///   - title: markdown `**…**` marks the accent word.
    ///   - isLarge: display size for the first-run screen, heading size inside an empty folder.
    public init(
        label: Text? = nil,
        title: AttributedString,
        message: Text? = nil,
        isLarge: Bool = true,
        @ViewBuilder actions: () -> Actions
    ) {
        self.label = label
        self.title = title
        self.message = message
        self.isLarge = isLarge
        self.actions = actions()
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: JGSpacing.s) {
            if let label {
                JGSectionHeader(label)
            }
            JGAccentText(attributed: title)
                .jgTextStyle(isLarge ? .display : .heading)
                .foregroundStyle(JGColor.textPrimary)
                .accessibilityAddTraits(.isHeader)
            if let message {
                message
                    .jgTextStyle(.body)
                    .foregroundStyle(JGColor.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: JGSpacing.xs) {
                actions
            }
            .padding(.top, JGSpacing.xs)
        }
        .frame(maxWidth: JGMetrics.readableTextWidth, alignment: .leading)
    }
}

#Preview {
    JGEmptyState(
        label: Text(verbatim: "Library"),
        title: (try? AttributedString(markdown: "Add a **folder**.")) ?? "",
        message: Text(verbatim: "Files stay where they are.")
    ) {
        Button(String("Add Folder…")) {}.buttonStyle(.jg(.primary))
    }
    .padding(JGSpacing.xxl)
    .background(JGColor.bgBase)
}
