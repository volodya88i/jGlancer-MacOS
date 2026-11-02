import Foundation

/// A virtual album: an ordered list of references to library assets; files stay where they are
/// (docs/FEATURES.md §6).
public struct Album: Hashable, Sendable, Identifiable {
    public let id: Int64
    public let name: String
    public let createdAt: Date
    /// The chosen cover, else the first present item; nil for an empty album.
    public let coverAssetID: Int64?
    /// Present items (placeholders of vanished files not counted).
    public let itemCount: Int

    public init(id: Int64, name: String, createdAt: Date, coverAssetID: Int64?, itemCount: Int) {
        self.id = id
        self.name = name
        self.createdAt = createdAt
        self.coverAssetID = coverAssetID
        self.itemCount = itemCount
    }
}

/// An album item as it was, for undoing its removal.
public struct AlbumItemPosition: Hashable, Sendable {
    public let assetID: Int64
    public let position: Int64

    public init(assetID: Int64, position: Int64) {
        self.assetID = assetID
        self.position = position
    }
}
