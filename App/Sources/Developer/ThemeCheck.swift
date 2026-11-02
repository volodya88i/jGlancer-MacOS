import AppKit
import Foundation

/// -JGThemeCheck <png>: snapshots the window in the Black theme, then with a chosen accent, without a relaunch, so
/// the live refresh of SwiftUI and AppKit colors shows.
@MainActor
enum ThemeCheck {
    static func run(_ appModel: AppModel, snapshot: URL) async {
        try? await Task.sleep(for: .seconds(1))
        guard let window = DeveloperHooks.mainWindow else { return }
        appModel.settingsStore.update { $0.theme = .black }
        try? await Task.sleep(for: .milliseconds(800))
        DeveloperHooks.snapshot(window, to: snapshot.deletingPathExtension().appendingPathExtension("black.png"))
        appModel.settingsStore.update { $0.accentColor = "#FF2E93" }
        try? await Task.sleep(for: .milliseconds(800))
        DeveloperHooks.snapshot(window, to: snapshot.deletingPathExtension().appendingPathExtension("pink.png"))
        appModel.settingsStore.update {
            $0.theme = .light
            $0.accentColor = nil
        }
        try? await Task.sleep(for: .milliseconds(800))
        DeveloperHooks.snapshot(window, to: snapshot.deletingPathExtension().appendingPathExtension("light.png"))
    }
}
