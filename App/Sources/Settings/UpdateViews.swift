import AppKit
import JGDesign
import JGSettings
import SwiftUI

/// Settings → General → Updates: the switch, Check Now and its result.
struct UpdateSettings: View {
    let updates: UpdateService
    let store: SettingsStore

    var body: some View {
        SettingsGroup(title: Text("Updates", comment: "Settings group; shown in capitals")) {
            SettingsToggle(
                title: Text("Look for a newer version once a day", comment: "Settings: the daily update check"),
                isOn: store.settings.checksForUpdates
            ) { isOn in store.update { $0.checksForUpdates = isOn } }
            HStack(spacing: JGSpacing.s) {
                Button {
                    Task { await updates.check(manual: true) }
                } label: {
                    Text("Check Now", comment: "Settings: looks for a newer version at once")
                }
                .buttonStyle(.jg(.secondary))
                .disabled(updates.status == .checking)
                statusText
                    .jgTextStyle(.body)
                    .foregroundStyle(JGColor.textSecondary)
            }
        }
    }

    private var statusText: Text {
        switch updates.status {
        case .idle: Text(verbatim: "")
        case .checking: Text("Checking…", comment: "Settings: the update check is running")
        case .upToDate: Text("You have the latest version.", comment: "Settings: the update check's result")
        case .failed: Text("Could not check. Try again later.", comment: "Settings: the update check failed")
        }
    }
}

/// A newer version: its number and notes; Open Release Page, Later, Skip This Version.
struct UpdateSheet: View {
    let updates: UpdateService
    let offer: UpdateService.Offer
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: JGSpacing.m) {
            Text("Version \(offer.version.description) is available", comment: "Update offer: title; the argument is a version")
                .jgTextStyle(.heading)
                .foregroundStyle(JGColor.textPrimary)
            if !offer.notes.isEmpty {
                ScrollView {
                    // Plain text: release notes are shown, never interpreted.
                    Text(verbatim: offer.notes)
                        .jgTextStyle(.body)
                        .foregroundStyle(JGColor.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: JGMetrics.batchRenameListHeight)
            }
            Text("You can turn this check off in Settings → General.", comment: "Update offer: note")
                .jgTextStyle(.body)
                .foregroundStyle(JGColor.textTertiary)
            HStack(spacing: JGSpacing.xs) {
                Button { updates.skip(offer) } label: {
                    Text("Skip This Version", comment: "Update offer")
                }
                .buttonStyle(.jg(.tertiary))
                Spacer()
                Button { dismiss() } label: { Text("Later", comment: "Update offer") }
                    .buttonStyle(.jg(.secondary))
                    .keyboardShortcut(.cancelAction)
                Button {
                    if let page = offer.page {
                        NSWorkspace.shared.open(page)
                    }
                    dismiss()
                } label: {
                    Text("Open Release Page", comment: "Update offer: opens the release on GitHub")
                }
                .buttonStyle(.jg(.primary))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(JGSpacing.l)
        .frame(width: JGMetrics.batchRenameWidth)
        .background(JGColor.bgPanel)
    }
}
