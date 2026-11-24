import CoreGraphics

/// Where every node of a `SizeTree` lies in a rectangle (D-127): squarified rectangles (Bruls, Huizing, van Wijk), each
/// folder with a band for its name at the top when there is room and a thin padding round its contents. Coordinates
/// grow downward (a flipped view). Rectangles smaller than `minSide` get no children laid out inside them.
public struct SizeMapLayout: Sendable {
    /// A laid-out node, in drawing order (parents before their children).
    public struct Box: Sendable {
        public let node: Int
        public let rect: CGRect
        /// The folder's name band, when it has one.
        public let header: CGRect?
        public let depth: Int
    }

    public let boxes: [Box]
    /// The rectangle of each node, by its index; nil when it was too small to lay out.
    public let rects: [CGRect?]

    public init() {
        boxes = []
        rects = []
    }

    public init(_ tree: SizeTree, in bounds: CGRect, header: CGFloat, padding: CGFloat, minSide: CGFloat) {
        var boxes: [Box] = []
        var rects = [CGRect?](repeating: nil, count: tree.nodes.count)
        func place(_ index: Int, in rect: CGRect, depth: Int) {
            guard rect.width >= 1, rect.height >= 1 else { return }
            rects[index] = rect
            let node = tree.nodes[index]
            guard !node.children.isEmpty else {
                boxes.append(Box(node: index, rect: rect, header: nil, depth: depth))
                return
            }
            let hasHeader = rect.height >= header * 2 && rect.width >= header * 3
            let band = hasHeader ? CGRect(x: rect.minX, y: rect.minY, width: rect.width, height: header) : nil
            boxes.append(Box(node: index, rect: rect, header: band, depth: depth))
            let inner = CGRect(
                x: rect.minX, y: rect.minY + (hasHeader ? header : 0), width: rect.width, height: rect.height - (hasHeader ? header : 0)
            ).insetBy(dx: padding, dy: padding)
            guard inner.width >= minSide, inner.height >= minSide else { return }
            let parts = Self.squarify(node.children.map { Double(tree.nodes[$0].size) }, in: inner)
            for (child, part) in zip(node.children, parts) {
                place(child, in: part, depth: depth + 1)
            }
        }
        if !tree.isEmpty {
            place(0, in: bounds, depth: 0)
        }
        self.boxes = boxes
        self.rects = rects
    }

    /// The deepest node whose rectangle holds `point`.
    public func hit(_ point: CGPoint, in tree: SizeTree) -> Int? {
        guard !tree.isEmpty, let root = rects.first ?? nil, root.contains(point) else { return nil }
        var current = 0
        while let next = tree.nodes[current].children.first(where: { rects[$0]?.contains(point) == true }) {
            current = next
        }
        return current
    }

    /// Rectangles for `values` (largest first works best) filling `rect`, each with an area in proportion to its value.
    public static func squarify(_ values: [Double], in rect: CGRect) -> [CGRect] {
        let total = values.reduce(0, +)
        guard total > 0, rect.width > 0, rect.height > 0 else { return values.map { _ in .zero } }
        let scale = Double(rect.width * rect.height) / total
        let areas = values.map { $0 * scale }
        var result = [CGRect](repeating: .zero, count: values.count)
        var remaining = rect
        var start = 0
        while start < areas.count {
            let side = Double(min(remaining.width, remaining.height))
            var end = start + 1
            var rowArea = areas[start]
            var worst = Self.worst(areas[start ..< end], sum: rowArea, side: side)
            while end < areas.count {
                let candidate = Self.worst(areas[start ... end], sum: rowArea + areas[end], side: side)
                guard candidate <= worst else { break }
                worst = candidate
                rowArea += areas[end]
                end += 1
            }
            remaining = place(row: start ..< end, areas: areas, rowArea: rowArea, in: remaining, into: &result)
            start = end
        }
        return result
    }

    /// Lays the row `range` along the shorter side of `remaining` (a column at the left, or a row at the top) and returns
    /// the room left.
    private static func place(
        row range: Range<Int>, areas: [Double], rowArea: Double, in remaining: CGRect, into result: inout [CGRect]
    ) -> CGRect {
        if remaining.width >= remaining.height {
            let width = remaining.height > 0 ? CGFloat(rowArea) / remaining.height : 0
            var y = remaining.minY
            for index in range {
                let height = width > 0 ? CGFloat(areas[index]) / width : 0
                result[index] = CGRect(x: remaining.minX, y: y, width: width, height: height)
                y += height
            }
            return CGRect(x: remaining.minX + width, y: remaining.minY, width: max(remaining.width - width, 0), height: remaining.height)
        }
        let height = remaining.width > 0 ? CGFloat(rowArea) / remaining.width : 0
        var x = remaining.minX
        for index in range {
            let width = height > 0 ? CGFloat(areas[index]) / height : 0
            result[index] = CGRect(x: x, y: remaining.minY, width: width, height: height)
            x += width
        }
        return CGRect(x: remaining.minX, y: remaining.minY + height, width: remaining.width, height: max(remaining.height - height, 0))
    }

    /// The worst aspect ratio of a row of `areas` laid along `side`.
    private static func worst(_ areas: ArraySlice<Double>, sum: Double, side: Double) -> Double {
        guard sum > 0, side > 0, let largest = areas.max(), let smallest = areas.min(), smallest > 0 else { return .infinity }
        let squared = side * side
        return max(squared * largest / (sum * sum), sum * sum / (squared * smallest))
    }
}
