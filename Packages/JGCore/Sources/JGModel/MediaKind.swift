/// The kind of a media asset known to the library.
///
/// Raw values are persisted in `asset.kind` (docs/ARCHITECTURE.md §4) and must never change.
public enum MediaKind: Int, CaseIterable, Codable, Hashable, Sendable {
    /// Still images: JPEG, HEIC, PNG, TIFF, RAW, …
    case photo = 0
    /// Movies playable through AVFoundation.
    case video = 1
    /// Audio files playable through AVFoundation.
    case audio = 2
}
