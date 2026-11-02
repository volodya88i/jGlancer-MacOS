/// Selection in the library grid, by asset id so it survives re-sorting and data changes
/// (docs/ARCHITECTURE.md §7). Finder semantics: click selects, ⌘-click toggles, ⇧-click and
/// ⇧-arrows extend a range from the anchor, marquee replaces or adds.
public struct SelectionModel: Equatable, Sendable {
    /// Selected asset ids.
    public private(set) var selected: Set<Int64> = []
    /// Start of range extensions.
    public private(set) var anchor: Int64?
    /// The keyboard cursor (last clicked or moved-to item).
    public private(set) var focus: Int64?
    /// Selection that range extensions and marquees add to.
    private var base: Set<Int64> = []

    public init() {}

    public var isEmpty: Bool {
        selected.isEmpty
    }

    public func contains(_ id: Int64) -> Bool {
        selected.contains(id)
    }

    /// Plain click or arrow: only `id`.
    public mutating func select(_ id: Int64) {
        selected = [id]
        base = []
        anchor = id
        focus = id
    }

    /// ⌘-click: adds or removes `id`.
    public mutating func toggle(_ id: Int64) {
        if selected.contains(id) {
            selected.remove(id)
        } else {
            selected.insert(id)
        }
        base = selected
        anchor = id
        focus = id
    }

    /// ⇧-click or ⇧-arrow: the range from the anchor to `id` in `order`, added to the selection
    /// that existed before the extension started.
    public mutating func extend(to id: Int64, in order: OrderedIDs) {
        guard let anchor, let start = order.index(of: anchor), let end = order.index(of: id) else {
            select(id)
            return
        }
        let range = min(start, end) ... max(start, end)
        selected = base.union(order.ids[range])
        focus = id
    }

    /// Starts a marquee drag; `adding` (⌘ or ⇧ held) keeps the current selection.
    public mutating func beginMarquee(adding: Bool) {
        base = adding ? selected : []
        if !adding {
            selected = []
        }
    }

    /// Updates a marquee drag to cover `ids`.
    public mutating func marquee(_ ids: some Sequence<Int64>) {
        selected = base.union(ids)
    }

    /// Ends a marquee drag so the next one starts from the current selection.
    public mutating func commitMarquee(focus id: Int64?) {
        base = selected
        if let id {
            anchor = id
            focus = id
        }
    }

    /// ⌘A.
    public mutating func selectAll(_ order: OrderedIDs) {
        selected = Set(order.ids)
        base = selected
        anchor = order.ids.first
        focus = order.ids.last
    }

    public mutating func clear() {
        self = SelectionModel()
    }

    /// Restores a saved selection.
    public mutating func restore(_ ids: some Sequence<Int64>, focus id: Int64?) {
        selected = Set(ids)
        base = selected
        anchor = id
        focus = id
    }

    /// Drops ids that are no longer shown (after filtering, deletion or a folder change).
    public mutating func retain(onlyIn order: OrderedIDs) {
        selected = selected.filter { order.index(of: $0) != nil }
        base = base.filter { order.index(of: $0) != nil }
        if let anchor, order.index(of: anchor) == nil {
            self.anchor = nil
        }
        if let focus, order.index(of: focus) == nil {
            self.focus = nil
        }
    }
}

/// The ordered ids currently shown, with O(1) position lookup.
public struct OrderedIDs: Sendable {
    public let ids: [Int64]
    private let positions: [Int64: Int]

    public init(_ ids: [Int64]) {
        self.ids = ids
        var positions: [Int64: Int] = [:]
        positions.reserveCapacity(ids.count)
        for (index, id) in ids.enumerated() {
            positions[id] = index
        }
        self.positions = positions
    }

    public func index(of id: Int64) -> Int? {
        positions[id]
    }
}
