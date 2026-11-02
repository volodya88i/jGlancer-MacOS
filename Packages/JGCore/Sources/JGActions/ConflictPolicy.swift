/// What a batch file operation does when the destination name already exists (docs/FEATURES.md §7).
public enum ConflictPolicy: String, CaseIterable, Codable, Sendable {
    /// Leave the existing file alone and skip the item.
    case skip
    /// Move the existing file to the Trash, then place the item.
    case replace
    /// Place the item under a unique name, e.g. `name 2.jpg`.
    case keepBoth
}
