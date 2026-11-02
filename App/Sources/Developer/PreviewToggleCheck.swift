import AppKit
import JGActions

/// `-JGPreviewToggleCheck YES`: presses Show Preview's shortcut (⌥⌘0, or ⌃⌘P with `-JGRemapPreview YES`) twice the way AppKit routes a key
/// equivalent (the window's views with
/// the grid focused, then the menu bar) and logs whether the preview pane hid and came back.
@MainActor
enum PreviewToggleCheck {
    static func run(library: LibraryModel, shortcuts: ShortcutStore, window: NSWindow?) async {
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
        try? await Task.sleep(for: .milliseconds(300))
        // SwiftUI fills the menus when they open; AppKit does the same before matching a key equivalent.
        for submenu in NSApp.mainMenu?.items.compactMap(\.submenu) ?? [] {
            submenu.delegate?.menuNeedsUpdate?(submenu)
        }
        let item = NSApp.mainMenu.flatMap { find("Show Preview", in: $0) ?? find("Показать просмотр", in: $0) }
        log("menu item: \(item.map { "\($0.title) [\($0.keyEquivalentModifierMask.rawValue >> 16)+\($0.keyEquivalent)]" } ?? "missing")")
        if let grid = window?.contentView.flatMap(collectionView(in:)) {
            window?.makeFirstResponder(grid)
        }
        log("first responder: \(window?.firstResponder.map { String(describing: type(of: $0)) } ?? "none")")
        log("visible before: \(library.state.previewVisible)")
        guard let shortcut = shortcuts.shortcut(for: .togglePreview) else {
            log("no shortcut")
            return
        }
        log("pressing \(shortcut.displayString)")
        for step in 1 ... 2 {
            press(shortcut, window)
            try? await Task.sleep(for: .milliseconds(300))
            log("after press \(step): \(library.state.previewVisible)")
        }
    }

    private static func press(_ shortcut: ActionShortcut, _ window: NSWindow?) {
        var flags: NSEvent.ModifierFlags = []
        if shortcut.modifiers.contains(.command) {
            flags.insert(.command)
        }
        if shortcut.modifiers.contains(.option) {
            flags.insert(.option)
        }
        if shortcut.modifiers.contains(.control) {
            flags.insert(.control)
        }
        if shortcut.modifiers.contains(.shift) {
            flags.insert(.shift)
        }
        for type in [NSEvent.EventType.keyDown, .keyUp] {
            let event = NSEvent.keyEvent(
                with: type, location: .zero, modifierFlags: flags, timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window?.windowNumber ?? 0, context: nil, characters: shortcut.key,
                charactersIgnoringModifiers: shortcut.key, isARepeat: false, keyCode: 0
            )
            if let event {
                // AppKit's order: the window's views first, then the menu bar.
                if type == .keyDown, window?.performKeyEquivalent(with: event) != true {
                    log("menu handles key: \(NSApp.mainMenu?.performKeyEquivalent(with: event) ?? false)")
                } else if type == .keyDown {
                    log("a view in the window took the key")
                }
            }
        }
    }

    static func collectionView(in view: NSView) -> NSView? {
        if view is NSCollectionView {
            return view
        }
        return view.subviews.lazy.compactMap(collectionView(in:)).first
    }

    private static func find(_ title: String, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.title == title {
                return item
            }
            if let found = item.submenu.flatMap({ find(title, in: $0) }) {
                return found
            }
        }
        return nil
    }

    private static func log(_ line: String) {
        FileHandle.standardError.write(Data("preview toggle check: \(line)\n".utf8))
    }
}
