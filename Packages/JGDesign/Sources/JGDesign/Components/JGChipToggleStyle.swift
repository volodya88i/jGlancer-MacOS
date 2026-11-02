import SwiftUI

/// Kind-filter toggles such as Video, Photo, Audio (W-98): quiet, no fill while off and no capitals. Off =
/// `text.secondary` (hover `text.primary`), on = `bg.raised` with `text.primary`.
public struct JGChipToggleStyle: ToggleStyle {
    public init() {}

    public func makeBody(configuration: Configuration) -> some View {
        Chip(configuration: configuration)
    }

    private struct Chip: View {
        let configuration: Configuration
        @State private var isHovered = false

        var body: some View {
            Button {
                configuration.isOn.toggle()
            } label: {
                configuration.label
                    .jgTextStyle(.button)
                    .lineLimit(1)
                    .foregroundStyle(configuration.isOn || isHovered ? JGColor.textPrimary : JGColor.textSecondary)
                    .padding(.horizontal, JGSpacing.s)
                    .frame(height: JGMetrics.controlHeightCompact)
                    .background(configuration.isOn ? AnyShapeStyle(JGColor.bgRaised) : AnyShapeStyle(.clear), in: JGShape(.small))
                    .contentShape(JGShape(.small))
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .accessibilityAddTraits(configuration.isOn ? [.isSelected] : [])
        }
    }
}

public extension ToggleStyle where Self == JGChipToggleStyle {
    /// `.toggleStyle(.jgChip)`
    static var jgChip: JGChipToggleStyle {
        JGChipToggleStyle()
    }
}

#Preview {
    HStack(spacing: JGSpacing.xs) {
        Toggle(String("Photo"), isOn: .constant(true)).toggleStyle(.jgChip)
        Toggle(String("Video"), isOn: .constant(true)).toggleStyle(.jgChip)
        Toggle(String("Audio"), isOn: .constant(false)).toggleStyle(.jgChip)
    }
    .padding(JGSpacing.l)
    .background(JGColor.bgBase)
}
