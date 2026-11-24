import Foundation
import Testing
@testable import JGActions

struct ShortcutMapTests {
    @Test func defaultsComeFromTheRegistryAndTheMenuBar() {
        let map = ShortcutMap()
        #expect(map.shortcut(for: .open) == ActionShortcut("o", .command))
        #expect(map.shortcut(for: .getInfo) == ActionRegistry.shortcut(for: .getInfo))
        #expect(map.shortcut(for: .togglePreview) == ActionShortcut("0", [.command, .option]))
        #expect(map.shortcut(for: .showNames) == nil)
        #expect(map.shortcut(for: .toggleSplitView) == ActionShortcut("s", [.command, .control]))
        #expect(map.shortcut(for: .toggleSidebar) == ActionShortcut("s", [.command, .option]))
        // Defaults never clash with each other or with reserved keys.
        let defaults = ShortcutCommand.allCases.compactMap(\.defaultShortcut)
        #expect(Set(defaults).count == defaults.count)
        #expect(Set(defaults).isDisjoint(with: ShortcutMap.reserved))
    }

    @Test func assignMovesAShortcutAndRefusesPlainOrReservedKeys() {
        var map = ShortcutMap()
        #expect(map.assign(ActionShortcut("i", .command), to: .copyPath) == .assigned(takenFrom: .getInfo))
        #expect(map.shortcut(for: .copyPath) == ActionShortcut("i", .command))
        #expect(map.shortcut(for: .getInfo) == nil)
        #expect(map.assign(ActionShortcut("k"), to: .getInfo) == .needsCommandOrControl)
        #expect(map.assign(ActionShortcut("q", .command), to: .getInfo) == .reserved)
        #expect(map.assign(ActionShortcut("1", .command), to: .getInfo) == .reserved)
        #expect(map.assign(ActionShortcut("k", [.control, .option]), to: .getInfo) == .assigned(takenFrom: nil))
        #expect(map.isCustomized(.getInfo))
    }

    @Test func clearingResettingAndSaving() throws {
        var map = ShortcutMap()
        map.assign(nil, to: .moveToTrash)
        #expect(map.shortcut(for: .moveToTrash) == nil)
        map.assign(ActionShortcut("n", .command), to: .addFolder)
        // ⌘N went to Add Folder: New Album cannot get it back by resetting while it is taken.
        map.reset(.newAlbum)
        #expect(map.shortcut(for: .newAlbum) == nil)
        let decoded = try JSONDecoder().decode(ShortcutMap.self, from: JSONEncoder().encode(map))
        #expect(decoded == map)
        map.resetAll()
        #expect(map == ShortcutMap())
        // Assigning the default again is not a customization.
        map.assign(ActionShortcut("i", .command), to: .getInfo)
        #expect(!map.isCustomized(.getInfo))
    }

    @Test func displayStrings() {
        #expect(ActionShortcut("m", [.command, .option]).displayString == "⌥⌘M")
        #expect(ActionShortcut("\u{8}", .command).displayString == "⌘⌫")
        #expect(ActionShortcut("0", [.control, .shift]).displayString == "⌃⇧0")
        #expect(ActionShortcut("\u{F708}", .control).displayString == "⌃F5")
    }
}
