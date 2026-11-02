import SwiftUI

/// A segmented control in the app's accent (macOS's own takes the system accent, D-102): the chosen segment is an accent
/// fill with `accent.on`, the others `text.secondary` on a `bg.raised` track.
public struct JGSegmented<Value: Hashable>: View {
    @Binding private var selection: Value
    private let options: [(Value, Text)]

    public init(selection: Binding<Value>, options: [(Value, Text)]) {
        _selection = selection
        self.options = options
    }

    public var body: some View {
        HStack(spacing: 0) {
            ForEach(options, id: \.0) { value, title in
                let isOn = value == selection
                Button { selection = value } label: {
                    title
                        .jgTextStyle(.button)
                        .lineLimit(1)
                        .foregroundStyle(isOn ? JGColor.accentOn : JGColor.textSecondary)
                        .padding(.horizontal, JGSpacing.s)
                        .frame(height: JGMetrics.controlHeightCompact)
                        .background(isOn ? AnyShapeStyle(JGColor.accent) : AnyShapeStyle(.clear), in: JGShape(.small))
                        .contentShape(JGShape(.small))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
            }
        }
        .background(JGColor.bgRaised, in: JGShape(.small))
        .fixedSize()
    }
}

/// A switch in the app's accent, its label on the left.
public struct JGSwitchToggleStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: JGSpacing.s) {
            configuration.label
            let knob = JGMetrics.switchHeight - 2 * JGMetrics.switchKnobInset
            Capsule()
                .fill(configuration.isOn ? AnyShapeStyle(JGColor.accent) : AnyShapeStyle(JGColor.bgRaised))
                .frame(width: JGMetrics.switchWidth, height: JGMetrics.switchHeight)
                .overlay {
                    if !configuration.isOn {
                        Capsule().strokeBorder(JGColor.lineStrong, lineWidth: JGMetrics.outlineWidth)
                    }
                }
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle()
                        .fill(configuration.isOn ? AnyShapeStyle(JGColor.accentOn) : AnyShapeStyle(JGColor.textSecondary))
                        .frame(width: knob, height: knob)
                        .padding(JGMetrics.switchKnobInset)
                }
        }
        .contentShape(Rectangle())
        .onTapGesture { configuration.isOn.toggle() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(configuration.isOn ? [.isToggle, .isSelected] : .isToggle)
        .accessibilityAction { configuration.isOn.toggle() }
    }
}

/// A check box in the app's accent, its label on the right.
public struct JGCheckboxToggleStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: JGSpacing.xs) {
            JGShape(.small)
                .fill(configuration.isOn ? AnyShapeStyle(JGColor.accent) : AnyShapeStyle(.clear))
                .overlay {
                    if configuration.isOn {
                        Image(systemName: "checkmark")
                            .font(.system(size: JGTextStyle.mono.size, weight: .bold))
                            .foregroundStyle(JGColor.accentOn)
                    } else {
                        JGShape(.small).strokeBorder(JGColor.lineStrong, lineWidth: JGMetrics.outlineWidth)
                    }
                }
                .frame(width: JGMetrics.checkboxSide, height: JGMetrics.checkboxSide)
            configuration.label
        }
        .contentShape(Rectangle())
        .onTapGesture { configuration.isOn.toggle() }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(configuration.isOn ? [.isToggle, .isSelected] : .isToggle)
        .accessibilityAction { configuration.isOn.toggle() }
    }
}

public extension ToggleStyle where Self == JGSwitchToggleStyle {
    /// `.toggleStyle(.jgSwitch)`
    static var jgSwitch: JGSwitchToggleStyle {
        JGSwitchToggleStyle()
    }
}

public extension ToggleStyle where Self == JGCheckboxToggleStyle {
    /// `.toggleStyle(.jgCheckbox)`
    static var jgCheckbox: JGCheckboxToggleStyle {
        JGCheckboxToggleStyle()
    }
}
