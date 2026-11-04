import CoreGraphics

/// A keyboard movement inside the grid.
public enum GridMove: Sendable {
    case left, right, up, down, pageUp, pageDown, home, end
}

/// Layout math of the library grid: square tiles in rows, stretched to fill the width (docs/ARCHITECTURE.md §7).
/// While the tile size is being changed, tiles take the target size exactly and the rows are centered, so they grow
/// smoothly instead of jumping when the column count changes (D-93). Pure and O(1) per query, so 100k items cost
/// nothing to lay out.
public struct GridGeometry: Equatable, Sendable {
    public let itemCount: Int
    public let width: CGFloat
    public let columns: Int
    /// Side of the square thumbnail area of a tile.
    public let tileSide: CGFloat
    /// Space under the thumbnail for the name (0 when names are hidden).
    public let captionHeight: CGFloat
    public let gutter: CGFloat
    /// Outer padding around the grid.
    public let inset: CGFloat
    /// Where the first column starts: the inset, plus half the room left over while tiles do not fill the row.
    public let leading: CGFloat

    /// - Parameters:
    ///   - targetTileSide: preferred tile side; with `fillsRow`, actual tiles stretch up to fill each row.
    ///   - fillsRow: false while the size is being changed: tiles are exactly `targetTileSide` (at most the width),
    ///     the rows centered.
    public init(
        itemCount: Int, width: CGFloat, targetTileSide: CGFloat, gutter: CGFloat, inset: CGFloat, captionHeight: CGFloat,
        fillsRow: Bool = true
    ) {
        self.itemCount = max(0, itemCount)
        self.width = width
        self.gutter = gutter
        self.inset = inset
        self.captionHeight = captionHeight
        let available = max(1, width - 2 * inset)
        let columns = max(1, Int((available + gutter) / (max(1, targetTileSide) + gutter)))
        self.columns = columns
        let filled = max(1, ((available - gutter * CGFloat(columns - 1)) / CGFloat(columns)).rounded(.down))
        tileSide = fillsRow ? filled : min(max(1, targetTileSide), filled)
        let used = CGFloat(columns) * tileSide + CGFloat(columns - 1) * gutter
        leading = inset + max(0, (available - used) / 2).rounded(.down)
    }

    /// Height of one tile including its caption.
    public var cellHeight: CGFloat {
        tileSide + captionHeight
    }

    public var rowCount: Int {
        (itemCount + columns - 1) / columns
    }

    /// Total scrollable height.
    public var contentHeight: CGFloat {
        guard rowCount > 0 else { return 0 }
        return 2 * inset + CGFloat(rowCount) * cellHeight + CGFloat(rowCount - 1) * gutter
    }

    /// Frame of the tile at `index` (top-left origin, y grows downward).
    public func frame(at index: Int) -> CGRect {
        let row = index / columns
        let column = index % columns
        return CGRect(
            x: leading + CGFloat(column) * (tileSide + gutter),
            y: inset + CGFloat(row) * (cellHeight + gutter),
            width: tileSide,
            height: cellHeight
        )
    }

    /// Indices of all tiles in the rows that intersect `rect` (for rendering and prefetch).
    public func indices(in rect: CGRect) -> Range<Int> {
        guard itemCount > 0, rect.maxY > inset else { return 0 ..< 0 }
        let rowPitch = cellHeight + gutter
        let firstRow = max(0, Int(((rect.minY - inset) / rowPitch).rounded(.down)))
        let lastRow = min(rowCount - 1, Int(((rect.maxY - inset) / rowPitch).rounded(.down)))
        guard firstRow <= lastRow else { return 0 ..< 0 }
        return (firstRow * columns) ..< min(itemCount, (lastRow + 1) * columns)
    }

    /// Indices whose tile actually intersects `rect` (for marquee selection).
    public func indices(intersecting rect: CGRect) -> [Int] {
        indices(in: rect).filter { frame(at: $0).intersects(rect) }
    }

    /// The tile under `point`, or nil for gutters and empty space.
    public func index(at point: CGPoint) -> Int? {
        indices(in: CGRect(x: point.x, y: point.y, width: 0, height: 0).insetBy(dx: 0, dy: -1))
            .first { frame(at: $0).contains(point) }
    }

    /// The tile nearest to `point`, also from a gutter or beyond the last tile (an album drop, D-110); nil when empty.
    public func nearestIndex(to point: CGPoint) -> Int? {
        guard itemCount > 0 else { return nil }
        let row = min(max(Int(((point.y - inset + gutter / 2) / (cellHeight + gutter)).rounded(.down)), 0), rowCount - 1)
        let column = min(max(Int(((point.x - leading + gutter / 2) / (tileSide + gutter)).rounded(.down)), 0), columns - 1)
        return min(row * columns + column, itemCount - 1)
    }

    /// Rows that fit in a viewport of `height`, at least one.
    public func rowsPerPage(viewportHeight height: CGFloat) -> Int {
        max(1, Int(height / (cellHeight + gutter)))
    }

    /// Where a keyboard move from `index` lands (clamped; left/right wrap across rows).
    public func index(from index: Int, moving move: GridMove, rowsPerPage: Int) -> Int {
        guard itemCount > 0 else { return 0 }
        let last = itemCount - 1
        let target = unclampedTarget(from: index, moving: move, rowsPerPage: rowsPerPage, last: last)
        let isVertical = [.up, .down, .pageUp, .pageDown].contains(move)
        if target < 0 {
            // Above the first row: stay in the same column of the first row.
            return isVertical ? index % columns : 0
        }
        if target > last {
            // Below the last item: jump to the last item unless already on the last row.
            return isVertical && index / columns == last / columns ? index : last
        }
        return target
    }

    private func unclampedTarget(from index: Int, moving move: GridMove, rowsPerPage: Int, last: Int) -> Int {
        switch move {
        case .left: index - 1
        case .right: index + 1
        case .up: index - columns
        case .down: index + columns
        case .pageUp: index - columns * rowsPerPage
        case .pageDown: index + columns * rowsPerPage
        case .home: 0
        case .end: last
        }
    }
}
