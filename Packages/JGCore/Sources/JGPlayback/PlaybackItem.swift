import Foundation
import JGModel

/// One playable file of a queue: a library asset or a file opened from outside the library.
public struct PlaybackItem: Hashable, Sendable, Identifiable {
    public let url: URL
    /// File name including extension.
    public let name: String
    public let kind: MediaKind
    /// Set for library assets (selection on return, cached thumbnails).
    public let assetID: Int64?
    public let modifiedAt: Date?
    public let typeIdentifier: String?
    /// Seconds, when the library already knows it.
    public let duration: Double?

    public var id: URL {
        url
    }

    public init(
        url: URL, name: String, kind: MediaKind, assetID: Int64? = nil, modifiedAt: Date? = nil,
        typeIdentifier: String? = nil, duration: Double? = nil
    ) {
        self.url = url
        self.name = name
        self.kind = kind
        self.assetID = assetID
        self.modifiedAt = modifiedAt
        self.typeIdentifier = typeIdentifier
        self.duration = duration
    }
}
