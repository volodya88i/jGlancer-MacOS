/// Presence of an asset's file on disk. Raw values are persisted in `asset.state`.
public enum AssetState: Int, Codable, Hashable, Sendable {
    /// The file exists where the library expects it.
    case present = 0
    /// The file vanished. The row is kept as a tombstone so albums, edits and ratings
    /// survive a later reappearance or an external move (docs/ARCHITECTURE.md §13).
    case missing = 1
}

/// Progress of background metadata extraction (stage 2). Raw values are persisted in `asset.meta_state`.
public enum MetadataState: Int, Codable, Hashable, Sendable {
    /// Only stage-1 facts (name, size, dates, kind) are known.
    case pending = 0
    /// Dimensions, duration, capture date etc. were extracted.
    case extracted = 1
    /// Extraction failed (corrupt or unsupported file); stage-1 facts remain valid.
    case failed = 2
}
