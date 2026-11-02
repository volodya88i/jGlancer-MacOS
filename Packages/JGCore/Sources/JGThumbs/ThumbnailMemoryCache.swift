import CoreGraphics
import Foundation

/// Decoded thumbnails in memory, bounded by decoded byte cost (width × height × 4) (docs/ARCHITECTURE.md §6).
/// Thread-safe; lookups never cross an actor hop, so visible tiles can be filled synchronously.
public final class ThumbnailMemoryCache: @unchecked Sendable {
    private final class Entry {
        let image: CGImage?
        init(_ image: CGImage?) {
            self.image = image
        }
    }

    /// NSCache is thread-safe; it is the reason for @unchecked Sendable.
    private let cache = NSCache<NSString, Entry>()

    /// - Parameter limitBytes: total decoded bytes kept before the system evicts entries.
    public init(limitBytes: Int) {
        cache.totalCostLimit = limitBytes
    }

    /// `.some(image)` for a cached thumbnail, `.some(nil)` for an asset known to have none, `nil` if unknown.
    public func lookup(_ key: ThumbnailKey) -> CGImage?? {
        cache.object(forKey: Self.name(key)).map(\.image)
    }

    public func insert(_ image: CGImage?, for key: ThumbnailKey) {
        let cost = image.map { $0.bytesPerRow * $0.height } ?? 64
        cache.setObject(Entry(image), forKey: Self.name(key), cost: cost)
    }

    public func removeAll() {
        cache.removeAllObjects()
    }

    private static func name(_ key: ThumbnailKey) -> NSString {
        "\(key.assetID):\(key.modifiedAt):\(key.bucket.rawValue)" as NSString
    }
}
