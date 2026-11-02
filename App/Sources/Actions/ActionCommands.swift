import JGActions
import JGModel
import SwiftUI

/// The registry's actions in the File menu (docs/ARCHITECTURE.md §15) for the viewer's file or the library
/// selection, with the shortcuts of Settings → Shortcuts (by default Open is ⌘O and Quick Preview ⌘Y here; Return
/// and Space stay with the grid and the players). Copy is
/// Edit ▸ Copy through the responder chain; Open With's app list lives in the context menu, where it is built on
/// demand instead of on every selection change.
struct ActionMenuItems: View {
    let appModel: AppModel

    var body: some View {
        let target = appModel.currentTarget
        let selection = target?.selection ?? ActionSelection(fileCount: 1, kinds: [.photo], place: .library)
        let sections = appModel.actions.menu(for: target ?? Self.placeholder(selection))
        ForEach(Array(sections.enumerated()), id: \.offset) { _, section in
            Divider()
            ForEach(section.filter { Self.isInMenuBar($0.id) }, id: \.id) { item in
                Button(appModel.actions.title(for: item.id, target: target ?? Self.placeholder(selection))) {
                    if let target = appModel.currentTarget {
                        appModel.actions.perform(item.id, on: target)
                    }
                }
                .keyboardShortcut(ShortcutCommand(rawValue: item.id.rawValue).flatMap(appModel.shortcuts.keyboardShortcut(for:)))
                // Off while renaming, so ⌘⌫ in the name field never trashes files.
                .disabled(target == nil || !item.isEnabled || appModel.fileOps?.renameRequest != nil)
            }
        }
    }

    static func isInMenuBar(_ id: ActionID) -> Bool {
        id != .copy && id != .openWith && id != .addToAlbum && id != .flag
    }

    /// Titles for the disabled items when nothing is selected.
    private static func placeholder(_ selection: ActionSelection) -> ActionTarget {
        ActionTarget(place: selection.place, assetIDs: [], kinds: selection.kinds, count: 0, sample: nil, urls: { [] })
    }
}

extension ActionShortcut.Modifiers {
    var swiftUI: EventModifiers {
        var modifiers: EventModifiers = []
        if contains(.command) {
            modifiers.insert(.command)
        }
        if contains(.option) {
            modifiers.insert(.option)
        }
        if contains(.shift) {
            modifiers.insert(.shift)
        }
        if contains(.control) {
            modifiers.insert(.control)
        }
        return modifiers
    }
}

/// File ▸ Flag: the colors and Remove Flag with their shortcuts (⌃F, ⌃1–⌃6, ⌃0 by default), for the viewer's file
/// or the library selection.
struct FlagMenu: View {
    let appModel: AppModel

    var body: some View {
        let target = appModel.currentTarget
        Menu(String(localized: "Flag", comment: "Menu of flag colors")) {
            ForEach(AssetFlag.menuOrder, id: \.self) { flag in
                if flag == .none {
                    Divider()
                }
                Button(flag.title) {
                    if let target = appModel.currentTarget {
                        appModel.actions.setFlag(flag, on: target)
                    }
                }
                .keyboardShortcut(appModel.shortcuts.keyboardShortcut(for: ShortcutCommand.command(for: flag)))
            }
        }
        .disabled(target?.assetIDs.isEmpty != false || appModel.fileOps?.renameRequest != nil || appModel.compareModel != nil)
    }
}
