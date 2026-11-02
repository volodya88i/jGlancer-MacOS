import Foundation

/// What Find Duplicates shows and would move to the Trash (W-78): groups of copies, the biggest groups first, each
/// with its oldest copy first. Every copy but the oldest starts ticked; one copy per group can never be ticked.
public struct DuplicatePlan: Equatable, Sendable {
    public struct Group: Equatable, Sendable, Identifiable {
        /// Oldest first.
        public let copies: [Asset]
        public var id: Int64 {
            copies.first?.id ?? 0
        }
    }

    public private(set) var groups: [Group]
    public private(set) var ticked: Set<Int64>

    public init(groups: [[Asset]]) {
        self.groups = groups.filter { $0.count > 1 }
            .map { Group(copies: $0.sorted { (Self.age($0), $0.id) < (Self.age($1), $1.id) }) }
            .sorted { lhs, rhs in
                if lhs.copies.count != rhs.copies.count {
                    return lhs.copies.count > rhs.copies.count
                }
                return (lhs.copies.first?.size ?? 0, rhs.id) > (rhs.copies.first?.size ?? 0, lhs.id)
            }
        ticked = Set(self.groups.flatMap { $0.copies.dropFirst().map(\.id) })
    }

    /// When the copy came to be: its creation date, else its modification date (whichever is earlier).
    static func age(_ asset: Asset) -> Date {
        min(asset.createdAt ?? asset.modifiedAt, asset.modifiedAt)
    }

    public func isTicked(_ id: Int64) -> Bool {
        ticked.contains(id)
    }

    /// Ticks or unticks a copy; false (and nothing changes) when that would tick every copy of its group.
    @discardableResult
    public mutating func toggle(_ id: Int64) -> Bool {
        if ticked.contains(id) {
            ticked.remove(id)
            return true
        }
        guard let group = groups.first(where: { $0.copies.contains { $0.id == id } }) else { return false }
        let others = group.copies.filter { $0.id != id }
        guard others.contains(where: { !ticked.contains($0.id) }) else { return false }
        ticked.insert(id)
        return true
    }

    /// The ticked copies, each with the copy of its group that stays (the first unticked one), to compare against.
    public var removals: [(copy: Asset, kept: Asset)] {
        groups.flatMap { group -> [(copy: Asset, kept: Asset)] in
            guard let kept = group.copies.first(where: { !ticked.contains($0.id) }) else { return [] }
            return group.copies.filter { ticked.contains($0.id) }.map { (copy: $0, kept: kept) }
        }
    }

    public var tickedBytes: Int64 {
        groups.flatMap(\.copies).filter { ticked.contains($0.id) }.reduce(0) { $0 + $1.size }
    }

    /// Copies beyond one per group.
    public var extraCopies: Int {
        groups.reduce(0) { $0 + $1.copies.count - 1 }
    }
}
