import Foundation

/// A media file known to the library: the full row, fetched lazily for visible items.
public struct Asset: Hashable, Sendable, Identifiable {
    public let id: Int64
    public let folderID: Int64
    /// File name including extension.
    public let name: String
    /// Absolute file URL.
    public let url: URL
    public let kind: MediaKind
    /// Uniform type identifier derived from the extension, e.g. `public.jpeg`.
    public let typeIdentifier: String?
    /// Size in bytes.
    public let size: Int64
    public let modifiedAt: Date
    public let createdAt: Date?
    /// Display size (photo orientation and video track transform applied); nil until stage 2.
    public let width: Int?
    public let height: Int?
    /// EXIF orientation (1–8) of photos.
    public let orientation: Int?
    /// Seconds, for video and audio.
    public let duration: Double?
    public let frameRate: Double?
    /// Four-character codec code, e.g. `avc1`, `hvc1`, `aac `.
    public let codec: String?
    public let capturedAt: Date?
    public let state: AssetState
    public let metadataState: MetadataState
    public let flag: AssetFlag
    /// The file's content is only in the cloud (`CloudFile`): nothing reads it until it is opened (D-124).
    public let isCloudOnly: Bool

    public init(
        id: Int64, folderID: Int64, name: String, url: URL, kind: MediaKind, typeIdentifier: String?, size: Int64,
        modifiedAt: Date, createdAt: Date?, width: Int?, height: Int?, orientation: Int?, duration: Double?,
        frameRate: Double?, codec: String?, capturedAt: Date?, state: AssetState, metadataState: MetadataState,
        flag: AssetFlag = .none, isCloudOnly: Bool = false
    ) {
        self.id = id
        self.folderID = folderID
        self.name = name
        self.url = url
        self.kind = kind
        self.typeIdentifier = typeIdentifier
        self.size = size
        self.modifiedAt = modifiedAt
        self.createdAt = createdAt
        self.width = width
        self.height = height
        self.orientation = orientation
        self.duration = duration
        self.frameRate = frameRate
        self.codec = codec
        self.capturedAt = capturedAt
        self.state = state
        self.metadataState = metadataState
        self.flag = flag
        self.isCloudOnly = isCloudOnly
    }
}

/// The lean per-item entry the grid holds for a whole query (docs/ARCHITECTURE.md §4).
///
/// The array order is the sort order; full rows are fetched only for visible items.
public struct AssetRef: Hashable, Sendable, Identifiable {
    public let id: Int64
    public let kind: MediaKind
    /// The folder holding the file (the list view groups files by folder, D-125).
    public let folderID: Int64

    public init(id: Int64, kind: MediaKind, folderID: Int64 = 0) {
        self.id = id
        self.kind = kind
        self.folderID = folderID
    }
}
