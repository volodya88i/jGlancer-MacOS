/// What the library window restores on relaunch (docs/PLAN.md Phase 2): scope, filters, sort,
/// tile size, names, selection. Decoding tolerates missing keys so new fields never reset the rest.
public struct LibraryViewState: Codable, Equatable, Sendable {
    /// Selections larger than this are not saved (⌘A on a huge library).
    public static let maxSavedSelection = 2000

    public var rootID: Int64?
    public var folderID: Int64?
    /// The album shown instead of a folder.
    public var albumID: Int64?
    public var includeSubfolders = true
    public var kinds: Set<MediaKind> = Set(MediaKind.allCases)
    public var sort: AssetQuery.Sort = .name
    public var ascending = true
    /// Preferred tile side in points.
    public var tileSide: Double = 160
    public var showNames = true
    public var selectedIDs: [Int64] = []
    public var focusedID: Int64?
    /// The preview pane on the right: shown, and its width in points.
    public var previewVisible = true
    public var previewWidth: Double = 360
    /// The sidebar's width in points (its edge drags, D-78).
    public var sidebarWidth: Double = 220
    /// Folders pinned to the top of the sidebar, by path (a missing one is skipped, not forgotten; D-87).
    public var pinnedFolders: [String] = []
    /// Split view (D-89): off, side by side or stacked, and the first pane's share of the room.
    public var splitMode: SplitMode = .off
    public var splitFraction: Double = 0.5
    /// The arrangement ⌃⌘S brings back (raw value of `SplitMode`).
    public var lastSplit = SplitMode.sideBySide.rawValue

    public enum SplitMode: String, Codable, CaseIterable, Sendable {
        case off, sideBySide, stacked
    }

    /// The top bar's star: only flagged files, or one flag.
    public var flagFilter: AssetQuery.FlagFilter?

    public init() {}

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let defaults = LibraryViewState()
        rootID = try container.decodeIfPresent(Int64.self, forKey: .rootID)
        folderID = try container.decodeIfPresent(Int64.self, forKey: .folderID)
        albumID = try container.decodeIfPresent(Int64.self, forKey: .albumID)
        includeSubfolders = try container.decodeIfPresent(Bool.self, forKey: .includeSubfolders) ?? defaults.includeSubfolders
        let kinds = try container.decodeIfPresent(Set<MediaKind>.self, forKey: .kinds) ?? defaults.kinds
        self.kinds = kinds.isEmpty ? defaults.kinds : kinds
        sort = (try? container.decodeIfPresent(AssetQuery.Sort.self, forKey: .sort)) ?? defaults.sort
        ascending = try container.decodeIfPresent(Bool.self, forKey: .ascending) ?? defaults.ascending
        tileSide = try container.decodeIfPresent(Double.self, forKey: .tileSide) ?? defaults.tileSide
        showNames = try container.decodeIfPresent(Bool.self, forKey: .showNames) ?? defaults.showNames
        selectedIDs = try container.decodeIfPresent([Int64].self, forKey: .selectedIDs) ?? []
        focusedID = try container.decodeIfPresent(Int64.self, forKey: .focusedID)
        previewVisible = try container.decodeIfPresent(Bool.self, forKey: .previewVisible) ?? defaults.previewVisible
        previewWidth = try container.decodeIfPresent(Double.self, forKey: .previewWidth) ?? defaults.previewWidth
        sidebarWidth = try container.decodeIfPresent(Double.self, forKey: .sidebarWidth) ?? defaults.sidebarWidth
        pinnedFolders = try container.decodeIfPresent([String].self, forKey: .pinnedFolders) ?? defaults.pinnedFolders
        splitMode = (try? container.decodeIfPresent(SplitMode.self, forKey: .splitMode)) ?? defaults.splitMode
        splitFraction = try container.decodeIfPresent(Double.self, forKey: .splitFraction) ?? defaults.splitFraction
        lastSplit = try container.decodeIfPresent(String.self, forKey: .lastSplit) ?? defaults.lastSplit
        flagFilter = try? container.decodeIfPresent(AssetQuery.FlagFilter.self, forKey: .flagFilter)
    }
}

extension AssetQuery.Sort: Codable {}
