import JGDesign
import JGSettings
import SwiftUI

/// Settings → Appearance: the Performance / Beauty presets, then each option on its own, theme and decor.
struct AppearanceSettings: View {
    let store: SettingsStore

    private var settings: AppSettings {
        store.settings
    }

    var body: some View {
        SettingsGroup(title: Text("Look", comment: "Settings: appearance preset; shown in capitals")) {
            PresetCards(selected: AppearancePreset.matching(settings), isLarge: false) { preset in
                store.update { preset.apply(to: &$0) }
            }
            if AppearancePreset.matching(settings) == nil {
                Text("Your own mix.", comment: "Settings: the options match neither preset")
                    .jgTextStyle(.body)
                    .foregroundStyle(JGColor.textTertiary)
            }
        }
        AccentColorGroup(store: store)
        SettingsGroup(title: Text("Effects", comment: "Settings group; shown in capitals")) {
            SettingsToggle(
                title: Text("Blurred cover behind audio", comment: "Settings: frosted cover art as the background of audio files"),
                isOn: settings.coverBackdrop
            ) { isOn in store.update { $0.coverBackdrop = isOn } }
            SettingsToggle(
                title: Text("Frosted glass in menus and panels", comment: "Settings: blurred backgrounds of toasts and panels"),
                isOn: settings.frostedGlass
            ) { isOn in store.update { $0.frostedGlass = isOn } }
            SettingsToggle(
                title: Text("See through the photo viewer", comment: "Settings: the photo viewer shows what is behind the window"),
                isOn: settings.translucentPhotoViewer
            ) { isOn in store.update { $0.translucentPhotoViewer = isOn } }
            SettingsToggle(
                title: Text("Show the next file while swiping", comment: "Settings: swipe animation between photos or songs"),
                isOn: settings.swipeAnimation
            ) { isOn in store.update { $0.swipeAnimation = isOn } }
            SettingsToggle(
                title: Text("Animate the library grid", comment: "Settings: tiles glide to new places when size, names or sort change"),
                isOn: settings.animatesGrid
            ) { isOn in store.update { $0.animatesGrid = isOn } }
            SettingsToggle(title: Text("Reduce motion", comment: "Settings: no fades and slides"), isOn: settings.reduceMotion) { isOn in
                store.update { $0.reduceMotion = isOn }
            }
        }
        SettingsGroup(title: Text("Filmstrip", comment: "Settings group; shown in capitals")) {
            segmented(\.filmstripReveal, [
                (.button, Text("Button", comment: "Settings: filmstrip shown and hidden by a button")),
                (.automatic, Text("Automatic", comment: "Settings: filmstrip appears near the bottom edge")),
            ])
        }
        SettingsGroup(title: Text("Kind Filters", comment: "Settings group: top bar video/photo/audio filters; shown in capitals")) {
            segmented(\.kindFilterStyle, [
                (.labels, Text("Words", comment: "Settings: kind filters as labelled chips")),
                (.icons, Text("Icons", comment: "Settings: kind filters as icons")),
            ])
        }
        SettingsGroup(title: Text("Theme", comment: "Settings group; shown in capitals")) {
            segmented(\.theme, [
                (.system, Text("System", comment: "Settings: follow the system")),
                (.dark, Text("Dark", comment: "Settings: dark theme")),
                (.black, Text("Black", comment: "Settings: black theme")),
                (.light, Text("Light", comment: "Settings: light theme")),
            ])
        }
        SettingsGroup(title: Text("Decor", comment: "Settings group; shown in capitals")) {
            let crosshairs = Text("Crosshair marks on selected files", comment: "Settings: decor")
            SettingsToggle(title: crosshairs, isOn: settings.crosshairMarks) { isOn in
                store.update { $0.crosshairMarks = isOn }
            }
            scrubberRow(Text("Audio player", comment: "Settings: decor, how the audio players draw their scrubber"), \.waveformStyle)
            scrubberRow(Text("Video player", comment: "Settings: decor, how the video player draws its scrubber"), \.videoWaveformStyle)
        }
    }

    /// A player's scrubber: its name on the left, Waveform | Timeline on the right (D-110).
    private func scrubberRow(_ title: Text, _ keyPath: WritableKeyPath<AppSettings, WaveformStyle>) -> some View {
        HStack {
            title
                .jgTextStyle(.body)
                .foregroundStyle(JGColor.textPrimary)
            Spacer()
            segmented(keyPath, [
                (.narrow, Text("Waveform", comment: "Settings: audio scrubber as a waveform")),
                (.timeline, Text("Timeline", comment: "Settings: audio scrubber as the plain video slider")),
            ])
        }
    }

    /// A segmented control over one setting.
    private func segmented<Value: Hashable>(_ keyPath: WritableKeyPath<AppSettings, Value>, _ options: [(Value, Text)]) -> some View {
        JGSegmented(
            selection: Binding(get: { settings[keyPath: keyPath] }, set: { value in store.update { $0[keyPath: keyPath] = value } }),
            options: options
        )
    }
}

/// The two presets as cards, one per row: one word and one short line (docs/DESIGN.md §8); the word in display type
/// on the first-launch screen. Rows, not columns, so long words (Russian) never shrink or clip.
struct PresetCards: View {
    let selected: AppearancePreset?
    let isLarge: Bool
    let choose: (AppearancePreset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: JGSpacing.s) {
            ForEach(AppearancePreset.allCases, id: \.self) { preset in
                Button { choose(preset) } label: {
                    HStack(alignment: .firstTextBaseline, spacing: JGSpacing.l) {
                        Self.name(preset)
                            .jgTextStyle(isLarge ? .display : .heading)
                            .foregroundStyle(JGColor.textPrimary)
                            .lineLimit(1)
                            .fixedSize()
                            .frame(minWidth: isLarge ? JGMetrics.presetNameWidthLarge : JGMetrics.presetNameWidth, alignment: .leading)
                        Self.line(preset)
                            .jgTextStyle(.body)
                            .foregroundStyle(JGColor.textSecondary)
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, isLarge ? JGSpacing.l : JGSpacing.m)
                    .padding(.vertical, isLarge ? JGSpacing.m : JGSpacing.s)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(JGColor.bgPanel, in: JGShape(.large))
                    .overlay {
                        JGShape(.large).strokeBorder(
                            selected == preset ? JGColor.accent : JGColor.lineHair,
                            lineWidth: JGMetrics.outlineWidth
                        )
                    }
                    .contentShape(JGShape(.large))
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(selected == preset ? .isSelected : [])
            }
        }
    }

    static func name(_ preset: AppearancePreset) -> Text {
        switch preset {
        case .performance: Text("Performance", comment: "Appearance preset: fewer effects")
        case .beauty: Text("Beauty", comment: "Appearance preset: blur and motion")
        }
    }

    static func line(_ preset: AppearancePreset) -> Text {
        switch preset {
        case .performance: Text("Fewer effects, faster.", comment: "Appearance preset, one line")
        case .beauty: Text("Blur and smooth motion.", comment: "Appearance preset, one line")
        }
    }
}
