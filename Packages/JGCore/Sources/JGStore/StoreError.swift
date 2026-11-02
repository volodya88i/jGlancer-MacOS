/// Errors raised by `LibraryStore`.
public enum StoreError: Error, Equatable, Sendable {
    /// The folder is already a library root.
    case rootAlreadyExists(path: String)
    /// The folder lies inside, or contains, an existing root.
    case rootOverlapsExisting(path: String, existing: String)
    /// No root with this id.
    case rootNotFound(id: Int64)
}
