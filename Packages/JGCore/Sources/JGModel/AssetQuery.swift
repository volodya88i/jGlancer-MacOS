import Foundation

/// What the library grid shows: a scope, a kind filter and a sort order (docs/FEATURES.md §1).
public struct AssetQuery: Hashable, Sendable {
    /// Which folders the query covers.
    public enum Scope: Hashable, Sendable {
        /// Every root in the library.
        case library
        /// One root folder and everything below it.
        case root(id: Int64)
        /// The items of a virtual album, in the album's order (the sort is not applied); placeholders of
        /// vanished files are included.
        case album(id: Int64)
        /// One folder, optionally with its subfolders.
        case folder(id: Int64, includeSubfolders: Bool)
    }

    /// Sort keys. Ties are broken by natural name order, then id.
    public enum Sort: String, CaseIterable, Hashable, Sendable {
        /// Natural order: "IMG_2" before "IMG_10", case- and diacritic-insensitive.
        case name
        case dateModified
        /// Capture date (EXIF / media creation date), falling back to the modification date.
        case dateCaptured
        case size
        /// Photos, then videos, then audio.
        case kind
    }

    /// Which flags a file must carry.
    public enum FlagFilter: Hashable, Codable, Sendable {
        /// Any flag.
        case flagged
        /// This flag only.
        case only(AssetFlag)
    }

    public var scope: Scope
    /// Kinds to include; an empty set matches nothing.
    public var kinds: Set<MediaKind>
    public var sort: Sort
    public var ascending: Bool
    /// Nil shows flagged and unflagged files.
    public var flagFilter: FlagFilter?
    /// Text the file name must contain (case-insensitive); nil or blank matches every file.
    public var search: String?

    public init(
        scope: Scope = .library,
        kinds: Set<MediaKind> = Set(MediaKind.allCases),
        sort: Sort = .name,
        ascending: Bool = true,
        flagFilter: FlagFilter? = nil,
        search: String? = nil
    ) {
        self.scope = scope
        self.kinds = kinds
        self.sort = sort
        self.ascending = ascending
        self.flagFilter = flagFilter
        self.search = search
    }

    /// The search text trimmed; nil when there is nothing to search for.
    public var searchText: String? {
        let text = search?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? nil : text
    }
}
