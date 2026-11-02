/// A file's flag (docs/FEATURES.md §12, DECISIONS D-57): a colored star, or none. Raw values are stored in
/// `asset.flag` and must never change.
public enum AssetFlag: Int, CaseIterable, Codable, Hashable, Sendable {
    case none = 0
    /// The app's accent color (⌃F).
    case accent = 1
    case red = 2
    case orange = 3
    case yellow = 4
    case green = 5
    case blue = 6
    case purple = 7

    /// The colors of ⌃1 … ⌃6, in that order.
    public static let colors: [AssetFlag] = [.red, .orange, .yellow, .green, .blue, .purple]

    /// What pressing `pressed` gives files flagged `current`: if every one already has it, the flag comes off;
    /// otherwise every file gets it. `.none` always removes.
    public static func applying(_ pressed: AssetFlag, to current: [AssetFlag]) -> AssetFlag {
        guard pressed != .none, !current.isEmpty else { return pressed }
        return current.allSatisfy { $0 == pressed } ? .none : pressed
    }
}
