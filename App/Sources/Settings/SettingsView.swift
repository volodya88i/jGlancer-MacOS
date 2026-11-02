import AppKit
import JGDesign
import JGModel
import JGSettings
import SwiftUI

/// Settings (⌘,; docs/FEATURES.md §14): sections listed on the left in the sidebar's style, the section on the
/// right. No system tab bar.
struct SettingsView: View {
    let appModel: AppModel
    @State private var section: SettingsSection

    init(appModel: AppModel, section: SettingsSection = .general) {
        self.appModel = appModel
        _section = State(initialValue: section)
    }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: JGSpacing.xxs) {
                ForEach(SettingsSection.allCases, id: \.self) { item in
                    SettingsSectionRow(section: item, isSelected: section == item) { section = item }
                }
                Spacer()
            }
            .padding(JGSpacing.xs)
            .padding(.top, JGSpacing.s)
            .frame(width: JGMetrics.settingsSidebarWidth)
            .background(JGColor.bgPanel)
            JGHairline(.vertical)
            ScrollView {
                VStack(alignment: .leading, spacing: JGSpacing.l) {
                    switch section {
                    case .general: GeneralSettings(store: appModel.settingsStore, updates: appModel.updates)
                    case .appearance: AppearanceSettings(store: appModel.settingsStore)
                    case .library: LibrarySettings(appModel: appModel)
                    case .playback: PlaybackSettings(appModel: appModel)
                    case .editWith: OpenWithSettingsView(store: appModel.openWith)
                    case .shortcuts: ShortcutsSettings(store: appModel.shortcuts)
                    }
                }
                .padding(JGSpacing.l)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(JGColor.bgBase)
        }
        .frame(width: JGMetrics.settingsWidth, height: JGMetrics.settingsHeight)
    }
}

enum SettingsSection: CaseIterable {
    case general
    case appearance
    case library
    case playback
    case editWith
    case shortcuts

    var title: Text {
        switch self {
        case .general: Text("General", comment: "Settings section")
        case .appearance: Text("Appearance", comment: "Settings section")
        case .library: Text("Library", comment: "Back button of the viewer; returns to the library")
        case .playback: Text("Playback", comment: "Settings section")
        case .editWith: Text("Edit With", comment: "Settings section: external apps per kind")
        case .shortcuts: Text("Shortcuts", comment: "Settings section: keyboard shortcuts")
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape.fill"
        case .appearance: "paintbrush.fill"
        case .library: "folder.fill"
        case .playback: "play.circle.fill"
        case .editWith: "arrow.up.forward.app.fill"
        case .shortcuts: "command"
        }
    }
}

private struct SettingsSectionRow: View {
    let section: SettingsSection
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: JGSpacing.xs) {
                Image(systemName: section.symbol)
                    .font(.system(size: JGTextStyle.body.size))
                    .frame(width: JGMetrics.iconSize)
                section.title.jgTextStyle(.body)
                Spacer(minLength: 0)
            }
            .foregroundStyle(isSelected ? JGColor.textPrimary : JGColor.textSecondary)
            .padding(.horizontal, JGSpacing.xs)
            .frame(height: JGMetrics.controlHeightCompact)
            .background(isSelected ? JGColor.bgRaised : JGColor.bgPanel, in: JGShape(.small))
            .contentShape(JGShape(.small))
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// A labelled group of settings.
struct SettingsGroup<Content: View>: View {
    let title: Text
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: JGSpacing.xs) {
            JGSectionHeader(title)
            content
        }
    }
}

/// A switch in the app's accent.
struct SettingsToggle: View {
    let title: Text
    let isOn: Bool
    let set: @MainActor (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: set)) {
            title.jgTextStyle(.body).foregroundStyle(JGColor.textPrimary)
        }
        .toggleStyle(.jgSwitch)
    }
}
