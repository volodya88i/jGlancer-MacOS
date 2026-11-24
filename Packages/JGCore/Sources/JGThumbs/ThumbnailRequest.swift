import Foundation
import JGModel

/// What to make a thumbnail of.
public struct ThumbnailRequest: Hashable, Sendable {
    public let assetID: Int64
    public let url: URL
    public let kind: MediaKind
    /// Uniform type identifier (RAW files use their embedded preview).
    public let typeIdentifier: String?
    /// Part of the cache key: a modified file gets a new thumbnail automatically.
    public let modifiedAt: Date
    /// Seconds, for choosing a video poster frame; nil if unknown.
    public let duration: Double?
    /// The bucket the display needs.
    public let bucket: ThumbnailBucket

    public init(
        assetID: Int64, url: URL, kind: MediaKind, typeIdentifier: String?, modifiedAt: Date,
        duration: Double?, bucket: ThumbnailBucket
    ) {
        self.assetID = assetID
        self.url = url
        self.kind = kind
        self.typeIdentifier = typeIdentifier
        self.modifiedAt = modifiedAt
        self.duration = duration
        self.bucket = bucket
    }

    /// Buckets kept on disk are medium and large; small requests reuse medium, scaled down at display
    /// (docs/ARCHITECTURE.md §6).
    public var storedBucket: ThumbnailBucket {
        max(bucket, .medium)
    }

    /// Cache key of the stored thumbnail.
    public var key: ThumbnailKey {
        ThumbnailKey(
            assetID: assetID,
            modifiedAt: Int64((modifiedAt.timeIntervalSince1970 * 1000).rounded()),
            bucket: storedBucket
        )
    }
}

/// Identity of a stored thumbnail: asset, file modification time (ms) and bucket.
public struct ThumbnailKey: Hashable, Sendable {
    public let assetID: Int64
    public let modifiedAt: Int64
    public let bucket: ThumbnailBucket
}

/// Scheduling priority: visible tiles first, then the prefetch window, then background work.
public enum ThumbnailPriority: Int, Comparable, Sendable {
    case background = 0
    case nearby = 1
    case visible = 2

    public static func < (lhs: ThumbnailPriority, rhs: ThumbnailPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}
