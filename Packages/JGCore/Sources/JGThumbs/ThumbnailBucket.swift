/// Thumbnail size buckets (docs/ARCHITECTURE.md §6).
///
/// Raw values are persisted in the `bucket` column of `cache.sqlite` and must never change.
public enum ThumbnailBucket: Int, CaseIterable, Comparable, Sendable {
    /// Longest side 160 px.
    case small = 0
    /// Longest side 320 px.
    case medium = 1
    /// Longest side 640 px.
    case large = 2

    /// The longest side of a thumbnail in this bucket, in pixels.
    public var maxPixelSize: Int {
        switch self {
        case .small: 160
        case .medium: 320
        case .large: 640
        }
    }

    /// The smallest bucket whose thumbnails cover `pixels` on their longest side,
    /// or `.large` when the request is bigger than every bucket.
    public static func covering(longestSidePixels pixels: Int) -> ThumbnailBucket {
        allCases.first { $0.maxPixelSize >= pixels } ?? .large
    }

    public static func < (lhs: ThumbnailBucket, rhs: ThumbnailBucket) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
