import AppKit
import JGActions
import JGDesign
import JGModel

/// The context menu (docs/FEATURES.md §8): native `NSMenu` built from the registry (DECISIONS D-12), shortcut
/// hints on the right, Open With as a submenu with app icons.
@MainActor
enum ActionMenu {
    static func make(for target: ActionTarget, performer: ActionPerformer) -> NSMenu? {
        let sections = performer.menu(for: target)
        guard !sections.isEmpty else { return nil }
        let menu = NSMenu()
        for (index, section) in sections.enumerated() {
            if index > 0 {
                menu.addItem(.separator())
            }
            for (id, isEnabled) in section {
                let item = ClosureMenuItem(title: performer.title(for: id, target: target)) {
                    performer.perform(id, on: target)
                }
                item.isEnabled = isEnabled
                if let shortcut = hint(for: id, performer: performer) {
                    item.keyEquivalent = shortcut.key
                    item.keyEquivalentModifierMask = shortcut.modifiers.eventFlags
                }
                if id == .openWith {
                    item.submenu = openWithMenu(for: target, performer: performer)
                } else if id == .addToAlbum {
                    item.submenu = albumMenu(for: target, performer: performer)
                } else if id == .flag {
                    item.submenu = flagMenu(for: target, performer: performer)
                    item.isEnabled = !target.assetIDs.isEmpty
                } else if id == .moveTo || id == .copyTo {
                    item.submenu = folderMenu(for: target, copying: id == .copyTo, performer: performer)
                }
                menu.addItem(item)
            }
        }
        menu.autoenablesItems = false
        return menu
    }

    /// The shortcut shown beside an item: the grid's plain keys for Open, Quick Preview and Remove from Album
    /// (Return, Space, Delete), the user's menu shortcut for the others.
    private static func hint(for id: ActionID, performer: ActionPerformer) -> ActionShortcut? {
        if let plain = ActionRegistry.shortcut(for: id), !plain.isMenuBarEquivalent {
            return plain
        }
        if let command = ShortcutCommand(rawValue: id.rawValue) {
            return performer.shortcuts?.shortcut(for: command)
        }
        return ActionRegistry.shortcut(for: id)
    }

    /// The colors with stars, then Remove Flag; shortcut hints from Settings → Shortcuts.
    static func flagMenu(for target: ActionTarget, performer: ActionPerformer) -> NSMenu {
        let menu = NSMenu()
        let appearance = NSApp.effectiveAppearance
        for flag in AssetFlag.menuOrder {
            if flag == .none {
                menu.addItem(.separator())
            }
            let item = ClosureMenuItem(title: flag.title) {
                performer.setFlag(flag, on: target)
            }
            item.image = flag == .none ? nil : flag.starImage(pointSize: JGTextStyle.body.size, appearance: appearance)
            if let shortcut = performer.shortcuts?.shortcut(for: ShortcutCommand.command(for: flag)) {
                item.keyEquivalent = shortcut.key
                item.keyEquivalentModifierMask = shortcut.modifiers.eventFlags
            }
            menu.addItem(item)
        }
        return menu
    }

    /// The albums (not the one shown), then New Album….
    static func albumMenu(for target: ActionTarget, performer: ActionPerformer) -> NSMenu {
        let menu = NSMenu()
        let albums = performer.albumsForAdding(target)
        for album in albums {
            let title: String = if album.contained == 0 {
                album.name
            } else if album.contained >= target.assetIDs.count {
                String(localized: "\(album.name) (already added)", comment: "Add to Album: the album holds every selected file")
            } else {
                String(localized: "\(album.name) (partly added)", comment: "Add to Album: the album holds some selected files")
            }
            menu.addItem(ClosureMenuItem(title: title) {
                performer.add(target, toAlbum: album.id)
            })
        }
        if !albums.isEmpty {
            menu.addItem(.separator())
        }
        menu.addItem(ClosureMenuItem(title: String(localized: "New Album…", comment: "Add to Album: create an album with the files")) {
            performer.addToNewAlbum(target)
        })
        return menu
    }

    /// Recent destination folders, then Choose Folder… (a panel with New Folder).
    static func folderMenu(for target: ActionTarget, copying: Bool, performer: ActionPerformer) -> NSMenu {
        let menu = NSMenu()
        let recents = performer.recentFolders
        for folder in recents {
            let item = ClosureMenuItem(title: folder.lastPathComponent) {
                Task { await performer.transfer(target, to: folder, copying: copying) }
            }
            item.toolTip = folder.path
            let icon = NSWorkspace.shared.icon(forFile: folder.path)
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
            menu.addItem(item)
        }
        if !recents.isEmpty {
            menu.addItem(.separator())
        }
        menu.addItem(ClosureMenuItem(title: String(localized: "Choose Folder…", comment: "Move to / Copy to: pick any folder")) {
            Task { await performer.transfer(target, to: nil, copying: copying) }
        })
        return menu
    }

    /// Configured apps (primary first; uninstalled ones greyed), the apps macOS suggests, Other….
    static func openWithMenu(for target: ActionTarget, performer: ActionPerformer) -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        for entry in performer.openWith.entries(for: target.kind, sample: target.sample) {
            switch entry {
            case .separator:
                menu.addItem(.separator())
            case .other:
                menu.addItem(ClosureMenuItem(title: String(localized: "Other…", comment: "Open With: choose any app")) {
                    performer.openWithOtherApp(target)
                })
            case let .app(name, url, _, isDefault):
                let title = OpenWithTitles.title(name: name, isInstalled: url != nil, isDefault: isDefault)
                let item = ClosureMenuItem(title: title) {
                    if let url {
                        Task { await performer.open(target, with: url) }
                    }
                }
                item.isEnabled = url != nil
                if let url {
                    let icon = NSWorkspace.shared.icon(forFile: url.path)
                    icon.size = NSSize(width: 16, height: 16)
                    item.image = icon
                }
                menu.addItem(item)
            }
        }
        return menu
    }
}

/// Titles of Open With entries, shared by the context menu and the menu bar.
enum OpenWithTitles {
    static func title(name: String, isInstalled: Bool, isDefault: Bool) -> String {
        if !isInstalled {
            return String(localized: "\(name) (not installed)", comment: "Open With: a configured app that was removed")
        }
        return isDefault ? String(localized: "\(name) (default)", comment: "Open With: the system's default app") : name
    }
}

/// A menu item that runs a closure.
final class ClosureMenuItem: NSMenuItem {
    private let handler: () -> Void

    init(title: String, handler: @escaping () -> Void) {
        self.handler = handler
        super.init(title: title, action: #selector(run), keyEquivalent: "")
        target = self
    }

    @available(*, unavailable)
    required init(coder _: NSCoder) {
        fatalError("not used")
    }

    @objc private func run() {
        handler()
    }
}

extension ActionShortcut.Modifiers {
    var eventFlags: NSEvent.ModifierFlags {
        var flags: NSEvent.ModifierFlags = []
        if contains(.command) {
            flags.insert(.command)
        }
        if contains(.option) {
            flags.insert(.option)
        }
        if contains(.shift) {
            flags.insert(.shift)
        }
        if contains(.control) {
            flags.insert(.control)
        }
        return flags
    }
}
