import SwiftUI

/// Buttons of the design system (docs/DESIGN.md §6–7): normal-case 13 pt medium, radius medium.
public struct JGButtonStyle: ButtonStyle {
    /// Visual weight.
    public enum Kind: Sendable {
        /// Filled `text.primary` block; one per screen.
        case primary
        /// Outlined.
        case secondary
        /// Text only, for low-emphasis actions.
        case tertiary
        /// Outlined, danger text.
        case destructive
    }

    private let kind: Kind
    @Environment(\.isEnabled) private var isEnabled

    public init(_ kind: Kind) {
        self.kind = kind
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .jgTextStyle(.button)
            .lineLimit(1)
            .foregroundStyle(isEnabled ? foreground : JGColor.textTertiary)
            .padding(.horizontal, kind == .tertiary ? JGSpacing.xs : JGSpacing.m)
            .frame(minHeight: JGMetrics.controlHeight)
            .background(kind == .primary ? JGColor.textPrimary : JGColor.bgPanel, in: JGShape(.small))
            .overlay {
                if kind == .secondary || kind == .destructive {
                    JGShape(.small).strokeBorder(JGColor.lineStrong, lineWidth: JGMetrics.outlineWidth)
                }
            }
            .opacity(configuration.isPressed ? JGMetrics.pressedOpacity : 1)
            .contentShape(JGShape(.small))
    }

    private var foreground: JGColorToken {
        switch kind {
        case .primary: JGColor.bgBase
        case .secondary, .tertiary: JGColor.textPrimary
        case .destructive: JGColor.danger
        }
    }
}

public extension ButtonStyle where Self == JGButtonStyle {
    /// `.buttonStyle(.jg(.primary))`
    static func jg(_ kind: JGButtonStyle.Kind) -> JGButtonStyle {
        JGButtonStyle(kind)
    }
}

#Preview {
    HStack(spacing: JGSpacing.xs) {
        Button(String("Add Folder")) {}.buttonStyle(.jg(.primary))
        Button(String("Reveal in Finder")) {}.buttonStyle(.jg(.secondary))
        Button(String("Cancel")) {}.buttonStyle(.jg(.tertiary))
        Button(String("Move to Trash")) {}.buttonStyle(.jg(.destructive))
        Button(String("Disabled")) {}.buttonStyle(.jg(.primary)).disabled(true)
    }
    .padding(JGSpacing.l)
    .background(JGColor.bgBase)
}
