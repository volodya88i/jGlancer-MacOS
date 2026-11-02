import SwiftUI

/// Icon toggles, a compact alternative to `JGChipToggleStyle` (Settings → Appearance → Kind Filters; W-98): 28 pt
/// squares 4 pt apart, quiet like the words: on = `bg.raised` with `text.primary`, off = no fill with `text.secondary`.
public struct JGJoinedToggles: View {
    public struct Item: Identifiable {
        public let id: String
        let symbol: String
        let label: Text
        let isOn: Bool
        let toggle: () -> Void

        public init(id: String, symbol: String, label: Text, isOn: Bool, toggle: @escaping () -> Void) {
            self.id = id
            self.symbol = symbol
            self.label = label
            self.isOn = isOn
            self.toggle = toggle
        }
    }

    let items: [Item]

    public init(_ items: [Item]) {
        self.items = items
    }

    public var body: some View {
        HStack(spacing: JGSpacing.xxs) {
            ForEach(items) { item in
                Toggled(item: item)
            }
        }
    }

    private struct Toggled: View {
        let item: Item
        @State private var isHovered = false

        var body: some View {
            Button(action: item.toggle) {
                Image(systemName: item.symbol)
                    .font(.system(size: JGTextStyle.body.size, weight: .medium))
                    .foregroundStyle(item.isOn || isHovered ? JGColor.textPrimary : JGColor.textSecondary)
                    .frame(width: JGMetrics.controlHeightCompact, height: JGMetrics.controlHeightCompact)
                    .background(item.isOn ? AnyShapeStyle(JGColor.bgRaised) : AnyShapeStyle(.clear), in: JGShape(.small))
                    .contentShape(JGShape(.small))
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .help(item.label)
            .accessibilityLabel(item.label)
            .accessibilityAddTraits(item.isOn ? [.isSelected] : [])
        }
    }
}

#Preview {
    JGJoinedToggles([
        .init(id: "video", symbol: "film.fill", label: Text(verbatim: "Video"), isOn: true) {},
        .init(id: "photo", symbol: "photo.fill", label: Text(verbatim: "Photo"), isOn: true) {},
        .init(id: "audio", symbol: "waveform", label: Text(verbatim: "Audio"), isOn: false) {},
    ])
    .padding(JGSpacing.l)
    .background(JGColor.bgBase)
}
