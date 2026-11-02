/// The indexing stages of a library scan (docs/ARCHITECTURE.md §5).
///
/// Stages are ordered by how early their results reach the UI.
public enum ScanStage: Int, CaseIterable, Comparable, Sendable {
    /// Directory enumeration: path, size, modification date and kind. Feeds the grid immediately.
    case enumeration = 1
    /// Metadata extraction without decoding pixels: dimensions, duration, capture date.
    case metadata = 2
    /// Lazily produced derivatives: thumbnails and waveforms.
    case derivatives = 3

    public static func < (lhs: ScanStage, rhs: ScanStage) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
