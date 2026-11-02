import AppKit
import JGDesign
import JGSettings
import SwiftUI

/// Settings → Appearance → Accent Color (W-93): ready colors, a hex field and the system's color panel. It applies at
/// once everywhere; the default color is saved as "none", so a later change of the app's own accent reaches it.
struct AccentColorGroup: View {
    let store: SettingsStore
    @State private var hex = ""
    @FocusState private var isHexFocused: Bool

    private var chosen: UInt32 {
        JGAccent.parse(store.settings.accentColor) ?? JGAccent.defaultColor
    }

    var body: some View {
        SettingsGroup(title: Text("Accent Color", comment: "Settings group; shown in capitals")) {
            HStack(spacing: JGSpacing.xxs) {
                ForEach(JGAccent.presets, id: \.color) { preset in
                    swatch(preset.color, name: Self.name(preset.color))
                }
            }
            HStack(spacing: JGSpacing.s) {
                TextField(text: $hex) { Text("Accent Color", comment: "Settings group; shown in capitals") }
                    .textFieldStyle(.roundedBorder)
                    .frame(width: JGMetrics.settingsSidebarWidth / 2)
                    .focused($isHexFocused)
                    .onSubmit(commit)
                    .onChange(of: isHexFocused) {
                        if !isHexFocused {
                            commit()
                        }
                    }
                Button {
                    AccentColorPanel.shared.show(current: chosen) { color in set(color) }
                } label: {
                    Text("Other Color…", comment: "Settings: opens the system color panel")
                }
                .buttonStyle(.jg(.secondary))
            }
        }
        .onAppear { hex = JGAccent.format(chosen) }
        .onChange(of: store.settings.accentColor) { hex = JGAccent.format(chosen) }
    }

    private func swatch(_ color: UInt32, name: Text) -> some View {
        let rgb = JGRGB(hex: color)
        return Button { set(color) } label: {
            Circle()
                .fill(Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue))
                .frame(width: JGMetrics.accentSwatchSide, height: JGMetrics.accentSwatchSide)
                .padding(JGSpacing.xxs / 2)
                .overlay {
                    if color == chosen {
                        Circle().strokeBorder(JGColor.textPrimary, lineWidth: JGMetrics.selectionEdgeWidth)
                    }
                }
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .help(name)
        .accessibilityLabel(name)
        .accessibilityAddTraits(color == chosen ? .isSelected : [])
    }

    private func set(_ color: UInt32) {
        store.update { $0.accentColor = color == JGAccent.defaultColor ? nil : JGAccent.format(color) }
    }

    /// Takes the color on Return or on leaving the field; anything else goes back to the current one.
    private func commit() {
        if let typed = JGAccent.parse(hex) {
            set(typed)
            hex = JGAccent.format(typed)
        } else {
            hex = JGAccent.format(chosen)
        }
    }

    private static func name(_ color: UInt32) -> Text {
        switch color {
        case 0x7A2CFF: Text("Purple", comment: "Accent color")
        case 0xFF2E93: Text("Pink", comment: "Accent color")
        case 0xE60012: Text("Red", comment: "Accent color")
        case 0xFF4F1A: Text("Orange", comment: "Accent color")
        case 0xF5B800: Text("Yellow", comment: "Accent color")
        case 0x18A558: Text("Green", comment: "Accent color")
        case 0x00A6C8: Text("Teal", comment: "Accent color")
        default: Text("Lavender", comment: "Accent color")
        }
    }
}

/// The system's color panel for the accent; every change applies at once.
@MainActor
final class AccentColorPanel: NSObject {
    static let shared = AccentColorPanel()
    private var onChange: ((UInt32) -> Void)?

    func show(current: UInt32, onChange: @escaping (UInt32) -> Void) {
        self.onChange = nil
        let panel = NSColorPanel.shared
        let rgb = JGRGB(hex: current)
        panel.showsAlpha = false
        panel.color = NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        self.onChange = onChange
        panel.orderFront(nil)
    }

    @objc private func colorChanged(_ panel: NSColorPanel) {
        guard let color = panel.color.usingColorSpace(.sRGB) else { return }
        func byte(_ value: CGFloat) -> UInt32 {
            UInt32(min(max((value * 255).rounded(), 0), 255))
        }
        onChange?(byte(color.redComponent) << 16 | byte(color.greenComponent) << 8 | byte(color.blueComponent))
    }
}
