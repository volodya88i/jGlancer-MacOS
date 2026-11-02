import AppKit
import JGDesign
import SwiftUI

/// jGlancer ▸ About jGlancer, as on Windows (W-101): the name in display type, the version, what the app is, its licence,
/// links to the author's GitHub and the source code, and the third-party notices (the `License-*.txt` resources). Esc closes it.
@MainActor
enum AboutPanel {
    private static var panel: NSPanel?

    static func show(store: SettingsStore) {
        let panel = panel ?? make(store: store)
        self.panel = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate()
    }

    private static func make(store: SettingsStore) -> NSPanel {
        let controller = NSHostingController(rootView: AboutView { panel?.orderOut(nil) }.appSettings(store))
        controller.sizingOptions = .preferredContentSize
        let panel = NSPanel(contentViewController: controller)
        panel.styleMask = [.titled, .closable, .fullSizeContentView]
        panel.titlebarAppearsTransparent = true
        panel.titleVisibility = .hidden
        panel.isFloatingPanel = false
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.backgroundColor = JGColor.bgPanel.nsColor
        panel.title = String(localized: "About \(AppIdentity.name)", comment: "App menu: the About panel; the argument is the app's name")
        return panel
    }

    static func notices() -> String {
        (Bundle.main.urls(forResourcesWithExtension: "txt", subdirectory: nil) ?? [])
            .filter { $0.lastPathComponent.hasPrefix("License-") }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { try? String(contentsOf: $0, encoding: .utf8) }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .joined(separator: "\n\n")
    }
}

private struct AboutView: View {
    let onClose: () -> Void
    @State private var showsNotices = false

    private static let profile = "https://github.com/volodya88i"
    private static let repository = UpdateService.repositoryPage
    private static let copyright = "© 2026 volodya88i"

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JGSpacing.s) {
            Text(verbatim: AppIdentity.name)
                .jgTextStyle(.display)
                .foregroundStyle(JGColor.textPrimary)
            Text("Version \(version)", comment: "About: the argument is the version number")
                .jgTextStyle(.mono)
                .foregroundStyle(JGColor.textSecondary)
            Text("A fast, light media browser for photos, video and music.", comment: "About: what the app is")
                .jgTextStyle(.body)
                .foregroundStyle(JGColor.textSecondary)
            Text(verbatim: Self.copyright)
                .jgTextStyle(.body)
                .foregroundStyle(JGColor.textTertiary)
            Text("Free software under the GNU General Public License 3.0.", comment: "About: the licence")
                .jgTextStyle(.body)
                .foregroundStyle(JGColor.textTertiary)
            HStack(spacing: JGSpacing.xs) {
                link(Text(verbatim: "GitHub"), Self.profile)
                link(Text("Source Code", comment: "About: opens the source code on GitHub"), Self.repository)
            }
            if showsNotices {
                ScrollView {
                    Text(verbatim: AboutPanel.notices())
                        .jgTextStyle(.mono)
                        .foregroundStyle(JGColor.textSecondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(JGSpacing.s)
                }
                .frame(height: JGMetrics.batchRenameListHeight)
                .background(JGColor.bgBase, in: JGShape(.small))
            }
            HStack(spacing: JGSpacing.xs) {
                Spacer()
                Button { showsNotices.toggle() } label: {
                    Text("Third-Party Notices", comment: "About: the licences of the software in the app")
                }
                .buttonStyle(.jg(.secondary))
                Button(action: onClose) { Text("Close", comment: "Closes a message") }
                    .buttonStyle(.jg(.primary))
                    .keyboardShortcut(.defaultAction)
                Button("", action: onClose)
                    .keyboardShortcut(.cancelAction)
                    .frame(width: 0, height: 0)
                    .opacity(0)
                    .accessibilityHidden(true)
            }
            .padding(.top, JGSpacing.s)
        }
        .padding(JGSpacing.l)
        .frame(width: JGMetrics.batchRenameWidth)
        .background(JGColor.bgPanel)
    }

    private func link(_ title: Text, _ address: String) -> some View {
        Button {
            if let url = URL(string: address) {
                NSWorkspace.shared.open(url)
            }
        } label: {
            title
        }
        .buttonStyle(.jg(.secondary))
        .help(Text(verbatim: address))
    }
}
