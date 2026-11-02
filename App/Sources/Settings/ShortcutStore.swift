import AppKit
import Carbon.HIToolbox
import JGActions
import Observation
import SwiftUI

/// Settings → Shortcuts: the user's menu-bar shortcuts, saved in user defaults (not for benchmark runs). Menus and
/// context-menu hints read them here.
@MainActor
@Observable
final class ShortcutStore {
    private(set) var map: ShortcutMap
    @ObservationIgnored private let isPersistent: Bool
    private static let key = "Shortcuts"

    init(isPersistent: Bool) {
        self.isPersistent = isPersistent
        map = (isPersistent ? UserDefaults.standard.data(forKey: Self.key) : nil)
            .flatMap { try? JSONDecoder().decode(ShortcutMap.self, from: $0) } ?? ShortcutMap()
    }

    func update<Result>(_ change: (inout ShortcutMap) -> Result) -> Result {
        let result = change(&map)
        if isPersistent, let data = try? JSONEncoder().encode(map) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
        return result
    }

    func shortcut(for command: ShortcutCommand) -> ActionShortcut? {
        map.shortcut(for: command)
    }

    /// For SwiftUI menu items; nil without a shortcut.
    func keyboardShortcut(for command: ShortcutCommand) -> KeyboardShortcut? {
        map.shortcut(for: command)?.keyboardShortcut
    }
}

extension ActionShortcut {
    var keyboardShortcut: KeyboardShortcut? {
        guard let character = key.first else { return nil }
        return KeyboardShortcut(KeyEquivalent(character), modifiers: modifiers.swiftUI)
    }

    /// A key press as a shortcut. Letters and digits are taken as on an ABC (US) layout, so a shortcut recorded
    /// with a Russian layout works with any layout, as menu shortcuts do on macOS.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        var modifiers: Modifiers = []
        if flags.contains(.command) {
            modifiers.insert(.command)
        }
        if flags.contains(.option) {
            modifiers.insert(.option)
        }
        if flags.contains(.shift) {
            modifiers.insert(.shift)
        }
        if flags.contains(.control) {
            modifiers.insert(.control)
        }
        guard let key = Self.key(of: event) else { return nil }
        self.init(key, modifiers)
    }

    private static func key(of event: NSEvent) -> String? {
        switch event.specialKey {
        case .delete?, .backspace?: return "\u{8}"
        case .carriageReturn?, .enter?: return "\r"
        case .tab?: return "\t"
        case .some: return event.charactersIgnoringModifiers
        case nil: break
        }
        if let plain = event.characters(byApplyingModifiers: [])?.lowercased(), !plain.isEmpty,
           plain.unicodeScalars.allSatisfy({ $0.isASCII && $0.value > 0x20 })
        {
            return plain
        }
        return ansiKeys[Int(event.keyCode)]
    }

    /// Key codes of the ABC layout's letters, digits and punctuation.
    private static let ansiKeys: [Int: String] = [
        kVK_ANSI_A: "a", kVK_ANSI_B: "b", kVK_ANSI_C: "c", kVK_ANSI_D: "d", kVK_ANSI_E: "e", kVK_ANSI_F: "f",
        kVK_ANSI_G: "g", kVK_ANSI_H: "h", kVK_ANSI_I: "i", kVK_ANSI_J: "j", kVK_ANSI_K: "k", kVK_ANSI_L: "l",
        kVK_ANSI_M: "m", kVK_ANSI_N: "n", kVK_ANSI_O: "o", kVK_ANSI_P: "p", kVK_ANSI_Q: "q", kVK_ANSI_R: "r",
        kVK_ANSI_S: "s", kVK_ANSI_T: "t", kVK_ANSI_U: "u", kVK_ANSI_V: "v", kVK_ANSI_W: "w", kVK_ANSI_X: "x",
        kVK_ANSI_Y: "y", kVK_ANSI_Z: "z", kVK_ANSI_0: "0", kVK_ANSI_1: "1", kVK_ANSI_2: "2", kVK_ANSI_3: "3",
        kVK_ANSI_4: "4", kVK_ANSI_5: "5", kVK_ANSI_6: "6", kVK_ANSI_7: "7", kVK_ANSI_8: "8", kVK_ANSI_9: "9",
        kVK_ANSI_Minus: "-", kVK_ANSI_Equal: "=", kVK_ANSI_LeftBracket: "[", kVK_ANSI_RightBracket: "]",
        kVK_ANSI_Semicolon: ";", kVK_ANSI_Quote: "'", kVK_ANSI_Backslash: "\\", kVK_ANSI_Comma: ",",
        kVK_ANSI_Period: ".", kVK_ANSI_Slash: "/", kVK_ANSI_Grave: "`",
    ]
}
