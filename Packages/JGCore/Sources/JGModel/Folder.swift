/// A directory inside a root folder (the root itself has an empty `relativePath`).
public struct Folder: Hashable, Sendable, Identifiable {
    public let id: Int64
    public let rootID: Int64
    /// Nil for the root's own folder.
    public let parentID: Int64?
    /// Path relative to the root, `/`-separated, empty for the root itself.
    public let relativePath: String
    /// Last path component (the root folder's own name for the root).
    public let name: String
    /// `.missing` when the directory vanished; its assets are tombstoned too.
    public let state: AssetState

    public init(id: Int64, rootID: Int64, parentID: Int64?, relativePath: String, name: String, state: AssetState) {
        self.id = id
        self.rootID = rootID
        self.parentID = parentID
        self.relativePath = relativePath
        self.name = name
        self.state = state
    }
}
