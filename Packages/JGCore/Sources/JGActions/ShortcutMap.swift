import JGModel

/// The commands whose menu-bar shortcut the user can change (Settings → Shortcuts). Plain keys of the grid and the
/// viewers (Space, Return, arrows, `[` `]`…) are not here: they belong to those views. Raw values are persisted.
public enum ShortcutCommand: String, CaseIterable, Codable, CodingKeyRepresentable, Sendable {
    // Files (the registry's actions in the File menu)
    case open
    case quickPreview
    case compare
    case editInPrimaryApp
    case moveTo
    case copyTo
    case rename
    case setAlbumCover
    case getInfo
    case revealInFinder
    case copyPath
    case moveToTrash
    // Flags (D-57)
    case flagAccent
    case flagRed
    case flagOrange
    case flagYellow
    case flagGreen
    case flagBlue
    case flagPurple
    case removeFlag
    // Library
    case find
    case addFolder
    case newAlbum
    case togglePreview
    case showNames
    case includeSubfolders
    /// View ▸ Split View on or off (D-89).
    case toggleSplitView
    /// View ▸ as Grid, as List (D-125).
    case asGrid
    case asList
    /// View ▸ Show Size Map (D-127).
    case toggleSizeMap
    /// View ▸ Show Sidebar (D-128).
    case toggleSidebar

    /// The registry action with the same id, for the file commands.
    public var action: ActionID? {
        ActionID(rawValue: rawValue)
    }

    public static let files: [ShortcutCommand] = allCases.filter { $0.action != nil }
    public static let flags: [ShortcutCommand] = allCases.filter { $0.flag != nil }
    public static let library: [ShortcutCommand] = allCases.filter { $0.action == nil && $0.flag == nil }

    /// The flag a flag command sets (`.none` for Remove Flag).
    public var flag: AssetFlag? {
        switch self {
        case .flagAccent: .accent
        case .flagRed: .red
        case .flagOrange: .orange
        case .flagYellow: .yellow
        case .flagGreen: .green
        case .flagBlue: .blue
        case .flagPurple: .purple
        case .removeFlag: AssetFlag.none
        default: nil
        }
    }

    /// The command that sets `flag`.
    public static func command(for flag: AssetFlag) -> ShortcutCommand {
        allCases.first { $0.flag == flag } ?? .removeFlag
    }

    /// The default (docs/FEATURES.md §15). Open and Quick Preview are ⌘O and ⌘Y in the menu bar; their plain
    /// Return and Space stay with the grid.
    public var defaultShortcut: ActionShortcut? {
        switch self {
        case .open: ActionShortcut("o", .command)
        case .quickPreview: ActionShortcut("y", .command)
        case .find: ActionShortcut("f", .command)
        case .addFolder: ActionShortcut("o", [.command, .shift])
        case .newAlbum: ActionShortcut("n", .command)
        case .togglePreview: ActionShortcut("0", [.command, .option])
        case .toggleSplitView: ActionShortcut("s", [.command, .control])
        // ⌘1 / ⌘2 as in Finder would take the viewer's zoom keys; with ⌃ they are free.
        case .asGrid: ActionShortcut("1", [.command, .control])
        case .asList: ActionShortcut("2", [.command, .control])
        case .toggleSizeMap: ActionShortcut("t", [.command, .option])
        // ⌃⌘S, Finder's, is the split view's here; ⌥ pairs it with the preview's ⌥⌘0 and the size map's ⌥⌘T.
        case .toggleSidebar: ActionShortcut("s", [.command, .option])
        case .showNames, .includeSubfolders: nil
        // ⌃F alone flags with the accent; ⌃F then 1–6 picks a color, ⌃F then 0 removes (the app's FlagChord).
        // The colors and Remove Flag have no shortcut of their own unless the user gives them one.
        case .flagAccent: ActionShortcut("f", .control)
        case .removeFlag, .flagRed, .flagOrange, .flagYellow, .flagGreen, .flagBlue, .flagPurple: nil
        default: action.flatMap(ActionRegistry.shortcut(for:)).flatMap { $0.isMenuBarEquivalent ? $0 : nil }
        }
    }
}

/// The user's shortcuts as changes on top of the defaults, saved as one value.
public struct ShortcutMap: Codable, Equatable, Sendable {
    /// Commands with a shortcut other than their default.
    public private(set) var custom: [ShortcutCommand: ActionShortcut] = [:]
    /// Commands whose shortcut was removed.
    public private(set) var cleared: Set<ShortcutCommand> = []

    public enum Outcome: Equatable, Sendable {
        /// Set; `takenFrom` lost the same shortcut.
        case assigned(takenFrom: ShortcutCommand?)
        /// Without ⌘ or ⌃ a shortcut would take the key from typing and from the players.
        case needsCommandOrControl
        /// The system or the app uses it already (Quit, Copy, the viewer's zoom…).
        case reserved
    }

    /// Kept by macOS or by views of the app; never assignable.
    public static let reserved: Set<ActionShortcut> = [
        ActionShortcut("q", .command), ActionShortcut("w", .command), ActionShortcut("h", .command),
        ActionShortcut("h", [.command, .option]), ActionShortcut("m", .command), ActionShortcut(",", .command),
        ActionShortcut("z", .command), ActionShortcut("z", [.command, .shift]), ActionShortcut("x", .command),
        ActionShortcut("c", .command), ActionShortcut("v", .command), ActionShortcut("a", .command),
        ActionShortcut("f", [.command, .control]), ActionShortcut("`", .command), ActionShortcut("\t", .command),
        // The photo viewer's zoom (⌘0 fit, ⌘1 actual size, ⌘9 fill, ⌘+ / ⌘−).
        ActionShortcut("0", .command), ActionShortcut("1", .command), ActionShortcut("9", .command),
        ActionShortcut("=", .command), ActionShortcut("+", .command), ActionShortcut("-", .command),
    ]

    public init() {}

    public func shortcut(for command: ShortcutCommand) -> ActionShortcut? {
        if cleared.contains(command) {
            return nil
        }
        return custom[command] ?? command.defaultShortcut
    }

    public func isCustomized(_ command: ShortcutCommand) -> Bool {
        custom[command] != nil || cleared.contains(command)
    }

    /// Gives `command` the shortcut (nil removes it). A shortcut held by another command moves over.
    @discardableResult
    public mutating func assign(_ shortcut: ActionShortcut?, to command: ShortcutCommand) -> Outcome {
        guard let shortcut else {
            store(nil, for: command)
            return .assigned(takenFrom: nil)
        }
        guard !shortcut.modifiers.isDisjoint(with: [.command, .control]) else { return .needsCommandOrControl }
        guard !Self.reserved.contains(shortcut) else { return .reserved }
        let holder = ShortcutCommand.allCases.first { $0 != command && self.shortcut(for: $0) == shortcut }
        if let holder {
            store(nil, for: holder)
        }
        store(shortcut, for: command)
        return .assigned(takenFrom: holder)
    }

    /// Back to the default; if another command holds the default now, the default is not taken from it.
    public mutating func reset(_ command: ShortcutCommand) {
        custom[command] = nil
        cleared.remove(command)
        if let shortcut = command.defaultShortcut,
           ShortcutCommand.allCases.contains(where: { $0 != command && self.shortcut(for: $0) == shortcut })
        {
            cleared.insert(command)
        }
    }

    public mutating func resetAll() {
        custom = [:]
        cleared = []
    }

    private mutating func store(_ shortcut: ActionShortcut?, for command: ShortcutCommand) {
        if shortcut == command.defaultShortcut {
            custom[command] = nil
            cleared.remove(command)
        } else if let shortcut {
            custom[command] = shortcut
            cleared.remove(command)
        } else {
            custom[command] = nil
            cleared.insert(command)
        }
    }
}

public extension ActionShortcut {
    /// As menus show it: modifiers in the order ⌃⌥⇧⌘, then the key (`⌥⌘M`, `⌘⌫`, `⌃F5`).
    var displayString: String {
        var text = ""
        if modifiers.contains(.control) {
            text += "⌃"
        }
        if modifiers.contains(.option) {
            text += "⌥"
        }
        if modifiers.contains(.shift) {
            text += "⇧"
        }
        if modifiers.contains(.command) {
            text += "⌘"
        }
        return text + Self.keyName(key)
    }

    static func keyName(_ key: String) -> String {
        guard let scalar = key.unicodeScalars.first else { return "" }
        if let name = specialKeyNames[scalar.value] {
            return name
        }
        // Function keys F1–F35 (AppKit's private-use characters).
        if (0xF704 ... 0xF726).contains(scalar.value) {
            return "F\(scalar.value - 0xF704 + 1)"
        }
        return key.uppercased()
    }

    private static let specialKeyNames: [UInt32: String] = [
        0x08: "⌫", 0x7F: "⌫", 0x0D: "↩", 0x09: "⇥", 0x20: "Space", 0x1B: "⎋",
        0xF700: "↑", 0xF701: "↓", 0xF702: "←", 0xF703: "→",
        0xF728: "⌦", 0xF729: "↖", 0xF72B: "↘", 0xF72C: "⇞", 0xF72D: "⇟",
    ]
}
