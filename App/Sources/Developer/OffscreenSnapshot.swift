import AppKit
import SwiftUI

/// `-JGSnapshotSize <W>x<H>` with `-JGSnapshot`: the main window's content in a borderless window of that size,
/// offscreen, then drawn to PNG. The main window may be tiled to half the screen, and a tiled window keeps its
/// size against the app's own resizing (the window server sets it back).
@MainActor
enum OffscreenSnapshot {
    static func run(_ appModel: AppModel, size text: String, to url: URL) async {
        guard let window = window(appModel, size: text) else { return }
        try? await Task.sleep(for: .seconds(1.5))
        DeveloperHooks.snapshot(window, to: url)
        window.orderOut(nil)
    }

    /// The main window's content in a borderless window `text` (`WxH`) big, offscreen.
    static func window(_ appModel: AppModel, size text: String) -> NSWindow? {
        let parts = text.split(separator: "x").compactMap { Double($0) }
        guard parts.count == 2 else { return nil }
        let window = NSWindow(
            contentRect: NSRect(x: -10000, y: -10000, width: parts[0], height: parts[1]), styleMask: [.borderless],
            backing: .buffered, defer: false
        )
        window.isReleasedWhenClosed = false
        window.appearance = DeveloperHooks.mainWindow?.effectiveAppearance
        window.contentView = NSHostingView(rootView: MainView(appModel: appModel)
            .appSettings(appModel.settingsStore)
            .environment(\.flagBook, appModel.flagBook)
            .environment(\.audioAnalyses, appModel.analyses))
        window.orderBack(nil)
        return window
    }
}
