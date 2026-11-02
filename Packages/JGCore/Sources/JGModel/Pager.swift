/// Index helpers for the viewer's pager (docs/ARCHITECTURE.md §8).
public enum Pager {
    /// Indices to keep decoded around `index`: itself first, then the nearest neighbors alternating forward
    /// and backward (`radius` on each side), clamped to `0 ..< count`. Order is decode priority.
    public static func window(around index: Int, count: Int, radius: Int = 2) -> [Int] {
        guard count > 0, (0 ..< count).contains(index) else { return [] }
        var result = [index]
        for distance in 1 ... max(radius, 1) where distance <= radius {
            if index + distance < count {
                result.append(index + distance)
            }
            if index - distance >= 0 {
                result.append(index - distance)
            }
        }
        return result
    }

    /// `index + offset` clamped to `0 ..< count` (no wrap-around at the ends).
    public static func move(_ index: Int, by offset: Int, count: Int) -> Int {
        guard count > 0 else { return 0 }
        return min(max(index + offset, 0), count - 1)
    }
}
