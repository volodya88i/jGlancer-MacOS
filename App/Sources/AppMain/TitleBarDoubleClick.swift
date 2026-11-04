import AppKit
import SwiftUI

/// A double-click on the app's top strip does what one on a title bar does (D-113): System Settings → Desktop &
/// Dock → "Double-click a window's title bar to" (zoom by default, or minimize, or nothing).
@MainActor
enum TitleBarDoubleClick {
    static func perform(in window: NSWindow?) {
        guard let window else { return }
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": window.miniaturize(nil)
        case "None": break
        default: window.zoom(nil)
        }
    }
}

extension View {
    /// The strip behaves like a title bar on a double-click; single clicks keep their meaning.
    func titleBarDoubleClick() -> some View {
        simultaneousGesture(TapGesture(count: 2).onEnded { TitleBarDoubleClick.perform(in: NSApp.keyWindow) })
    }
}
