import AppKit
import JGDesign
import JGModel
import JGSettings
import SwiftUI

/// Settings → Edit With (docs/FEATURES.md §9): per kind, a card with the apps that come first in Open With and the
/// starred primary one for "Edit in …" (⌘⌥E). An app that was uninstalled is shown greyed.
struct OpenWithSettingsView: View {
    let store: OpenWithStore

    var body: some View {
        Text("Apps listed first in Open With. The starred one opens with ⌘⌥E.", comment: "Settings: Edit With explanation")
            .jgTextStyle(.body)
            .foregroundStyle(JGColor.textSecondary)
        ForEach([MediaKind.photo, .video, .audio], id: \.self) { kind in
            section(kind)
                .padding(JGSpacing.m)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(JGColor.bgPanel, in: JGShape(.large))
                .overlay(JGShape(.large).strokeBorder(JGColor.lineHair, lineWidth: JGMetrics.outlineWidth))
        }
    }

    private func section(_ kind: MediaKind) -> some View {
        VStack(alignment: .leading, spacing: JGSpacing.xs) {
            JGSectionHeader(Self.kindName(kind))
            let apps = store.settings.apps(for: kind)
            let primary = store.settings.primary(for: kind)
            ForEach(apps, id: \.bundleID) { app in
                row(app, kind: kind, isPrimary: app == primary)
            }
            Button {
                choose(for: kind)
            } label: {
                Text("Add App…", comment: "Settings, Open With: adds an app for this kind")
            }
            .buttonStyle(.jg(.secondary))
        }
    }

    private func row(_ app: ExternalApp, kind: MediaKind, isPrimary: Bool) -> some View {
        let location = OpenWithStore.location(of: app)
        return HStack(spacing: JGSpacing.s) {
            if let location {
                Image(nsImage: NSWorkspace.shared.icon(forFile: location.path))
                    .resizable()
                    .frame(width: JGMetrics.iconSize, height: JGMetrics.iconSize)
            }
            Text(verbatim: app.name)
                .jgTextStyle(.body)
                .foregroundStyle(location == nil ? JGColor.textTertiary : JGColor.textPrimary)
            if location == nil {
                Text("Not installed", comment: "Settings, Open With: the app was removed")
                    .jgTextStyle(.body)
                    .foregroundStyle(JGColor.textTertiary)
            }
            Spacer()
            Button {
                store.update { $0.setPrimary(bundleID: app.bundleID, for: kind) }
            } label: {
                Image(systemName: isPrimary ? "star.fill" : "star")
                    .foregroundStyle(isPrimary ? JGColor.accentText : JGColor.textTertiary)
            }
            .buttonStyle(.plain)
            .help(Text("Primary App", comment: "Settings, Open With: the app used by Edit in … (⌘⌥E)"))
            .accessibilityLabel(Text("Primary App", comment: "Settings, Open With: the app used by Edit in … (⌘⌥E)"))
            .accessibilityAddTraits(isPrimary ? .isSelected : [])
            Button {
                store.update { $0.remove(bundleID: app.bundleID, for: kind) }
            } label: {
                Image(systemName: "minus.circle").foregroundStyle(JGColor.textSecondary)
            }
            .buttonStyle(.plain)
            .help(Text("Remove", comment: "Settings, Open With: removes the app"))
            .accessibilityLabel(Text("Remove", comment: "Settings, Open With: removes the app"))
        }
        .frame(height: JGMetrics.controlHeightCompact)
    }

    private func choose(for kind: MediaKind) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = true
        guard panel.runModal() == .OK else { return }
        let apps = panel.urls.compactMap(OpenWithStore.externalApp(at:))
        store.update { settings in
            for app in apps {
                settings.add(app, for: kind)
            }
        }
    }

    static func kindName(_ kind: MediaKind) -> Text {
        switch kind {
        case .photo: Text("Photo", comment: "Media kind")
        case .video: Text("Video", comment: "Media kind")
        case .audio: Text("Audio", comment: "Media kind")
        }
    }
}
