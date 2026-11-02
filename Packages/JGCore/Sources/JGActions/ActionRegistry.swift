import JGModel

/// Every user action of the app (docs/FEATURES.md §8, ARCHITECTURE §15). Raw values may be persisted
/// (customized shortcuts, `ShortcutCommand`) and must never change.
public enum ActionID: String, CaseIterable, Sendable {
    case open
    case quickPreview
    /// Songs in the window's mini player (D-88).
    case playInMiniPlayer
    /// Two photos side by side (W-77).
    case compare
    /// Songs into vocals, drums, bass… (D-97).
    case splitStems
    case openWith
    case editInPrimaryApp
    case addToAlbum
    case removeFromAlbum
    case setAlbumCover
    case moveTo
    case copyTo
    case rename
    case getInfo
    case revealInFinder
    case copyPath
    case copy
    case moveToTrash
    /// The Flag submenu (colors and Remove Flag).
    case flag
}

/// A keyboard shortcut as data; renderers turn it into key equivalents.
public struct ActionShortcut: Hashable, Codable, Sendable {
    public struct Modifiers: OptionSet, Hashable, Codable, Sendable {
        public let rawValue: Int
        public init(rawValue: Int) {
            self.rawValue = rawValue
        }

        public static let command = Modifiers(rawValue: 1)
        public static let option = Modifiers(rawValue: 2)
        public static let shift = Modifiers(rawValue: 4)
        public static let control = Modifiers(rawValue: 8)
    }

    /// The key: a character, `" "` for Space, `"\r"` for Return, `"\u{8}"` for Delete.
    public let key: String
    public let modifiers: Modifiers

    public init(_ key: String, _ modifiers: Modifiers = []) {
        self.key = key
        self.modifiers = modifiers
    }

    /// A shortcut the menu bar may own. Plain keys (Space, Return) are only hints in context menus: as
    /// key equivalents they would take the key from players and text fields.
    public var isMenuBarEquivalent: Bool {
        !modifiers.isDisjoint(with: [.command, .control])
    }
}

/// Parts of the app an action needs; a mode (Phase 10) or a phase not built yet leaves some out.
public enum ActionFeature: Hashable, Sendable {
    case openWith
    case fileOperations
    case albums
    case flags
}

/// What the actions apply to: the selection in the library or the file shown in a viewer.
public struct ActionSelection: Equatable, Sendable {
    public enum Place: Sendable {
        case library
        /// The library grid showing an album.
        case album
        case viewer
    }

    /// Number of files.
    public let fileCount: Int
    public let kinds: Set<MediaKind>
    public let place: Place

    public init(fileCount: Int, kinds: Set<MediaKind>, place: Place) {
        self.fileCount = fileCount
        self.kinds = kinds
        self.place = place
    }
}

public enum ActionAvailability: Equatable, Sendable {
    case hidden
    case disabled
    case enabled
}

/// The one registry behind the context menu, the menu bar and shortcuts: order, sections, shortcuts and
/// availability by selection and features. Titles and performing live in the app.
public enum ActionRegistry {
    /// Menu sections in order (docs/FEATURES.md §8); the destructive action is last and alone.
    public static let sections: [[ActionID]] = [
        [.open, .quickPreview, .playInMiniPlayer, .compare, .splitStems, .openWith, .editInPrimaryApp],
        [.addToAlbum, .removeFromAlbum, .setAlbumCover, .moveTo, .copyTo, .rename],
        [.flag],
        [.getInfo, .revealInFinder, .copyPath, .copy],
        [.moveToTrash],
    ]

    /// Default shortcuts (docs/FEATURES.md §15).
    public static func shortcut(for id: ActionID) -> ActionShortcut? {
        shortcuts[id]
    }

    private static let shortcuts: [ActionID: ActionShortcut] = [
        .open: ActionShortcut("\r"),
        .quickPreview: ActionShortcut(" "),
        .compare: ActionShortcut("c", [.command, .control]),
        .editInPrimaryApp: ActionShortcut("e", [.command, .option]),
        .moveTo: ActionShortcut("m", [.command, .option]),
        .getInfo: ActionShortcut("i", .command),
        .revealInFinder: ActionShortcut("r", [.command, .option]),
        .copyPath: ActionShortcut("c", [.command, .option]),
        .copy: ActionShortcut("c", .command),
        .moveToTrash: ActionShortcut("\u{8}", .command),
        .removeFromAlbum: ActionShortcut("\u{8}"),
    ]

    /// - Parameter primaryAppKinds: kinds that have a primary external app (Settings → Open With).
    public static func availability(
        _ id: ActionID, for selection: ActionSelection, features: Set<ActionFeature>, primaryAppKinds: Set<MediaKind>
    ) -> ActionAvailability {
        guard selection.fileCount >= 1 else { return .hidden }
        switch id {
        case .getInfo, .revealInFinder, .copyPath, .copy:
            return .enabled
        case .flag:
            return features.contains(.flags) ? .enabled : .hidden
        case .open, .quickPreview, .playInMiniPlayer, .compare, .splitStems:
            return openingAvailability(id, selection)
        case .openWith, .editInPrimaryApp:
            return openWithAvailability(id, selection, features, primaryAppKinds)
        case .addToAlbum, .removeFromAlbum, .setAlbumCover:
            return albumAvailability(id, selection, features)
        case .moveTo, .copyTo, .moveToTrash, .rename:
            guard features.contains(.fileOperations) else { return .hidden }
            // A viewer copies and trashes its file; moving and renaming happen in the library.
            if selection.place == .viewer, id == .moveTo || id == .rename {
                return .hidden
            }
            // Several files are renamed by a pattern (`BatchRenamePattern`).
            return .enabled
        }
    }

    /// In a viewer the file is already open, but its song can go on in the mini player or be split; the mini player
    /// and Split into Stems take songs only; Compare takes exactly two photos.
    private static func openingAvailability(_ id: ActionID, _ selection: ActionSelection) -> ActionAvailability {
        guard selection.place != .viewer || id == .playInMiniPlayer || id == .splitStems else { return .hidden }
        switch id {
        case .playInMiniPlayer, .splitStems: return selection.kinds == [.audio] ? .enabled : .hidden
        case .compare: return selection.kinds == [.photo] && selection.fileCount == 2 ? .enabled : .hidden
        default: return .enabled
        }
    }

    private static func openWithAvailability(
        _ id: ActionID, _ selection: ActionSelection, _ features: Set<ActionFeature>, _ primaryAppKinds: Set<MediaKind>
    ) -> ActionAvailability {
        guard features.contains(.openWith) else { return .hidden }
        guard id == .editInPrimaryApp else { return .enabled }
        guard selection.kinds.count == 1, let kind = selection.kinds.first, primaryAppKinds.contains(kind) else {
            return .hidden
        }
        return .enabled
    }

    /// Adding works anywhere; removing and choosing the cover only in an album, the cover for one item.
    private static func albumAvailability(
        _ id: ActionID, _ selection: ActionSelection, _ features: Set<ActionFeature>
    ) -> ActionAvailability {
        guard features.contains(.albums) else { return .hidden }
        switch id {
        case .removeFromAlbum: return selection.place == .album ? .enabled : .hidden
        case .setAlbumCover:
            guard selection.place == .album else { return .hidden }
            return selection.fileCount == 1 ? .enabled : .disabled
        default: return .enabled
        }
    }

    /// The visible actions per section, empty sections dropped.
    public static func menu(
        for selection: ActionSelection, features: Set<ActionFeature>, primaryAppKinds: Set<MediaKind>
    ) -> [[(id: ActionID, isEnabled: Bool)]] {
        sections.compactMap { section in
            let items = section.compactMap { id -> (id: ActionID, isEnabled: Bool)? in
                switch availability(id, for: selection, features: features, primaryAppKinds: primaryAppKinds) {
                case .hidden: nil
                case .disabled: (id, false)
                case .enabled: (id, true)
                }
            }
            return items.isEmpty ? nil : items
        }
    }
}
