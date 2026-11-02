/// A root's folders, and the ones that hold media themselves (`FolderNode.tree(from:withMedia:)`).
public struct FolderContents: Equatable, Sendable {
    public let folders: [Folder]
    public let withMedia: Set<Int64>

    public init(folders: [Folder], withMedia: Set<Int64>) {
        self.folders = folders
        self.withMedia = withMedia
    }
}

/// A folder with its subfolders, for the sidebar tree.
public struct FolderNode: Hashable, Sendable, Identifiable {
    public let folder: Folder
    /// Nil (not empty) when there are no subfolders, so outline views show no disclosure triangle.
    public let children: [FolderNode]?

    public var id: Int64 {
        folder.id
    }

    /// Builds the tree of one root from its flat folder rows; children sorted in natural name order. With
    /// `withMedia` (the folders that hold media themselves), subfolders without media in them or anywhere below are
    /// left out (D-78, W-67); the root always stays.
    public static func tree(from folders: [Folder], withMedia: Set<Int64>? = nil) -> FolderNode? {
        let byParent = Dictionary(grouping: folders.filter { $0.parentID != nil }) { $0.parentID ?? 0 }
        func node(_ folder: Folder) -> FolderNode? {
            let children = (byParent[folder.id] ?? [])
                .sorted { NaturalSortKey.make($0.name) < NaturalSortKey.make($1.name) }
                .compactMap(node)
            if let withMedia, folder.parentID != nil, children.isEmpty, !withMedia.contains(folder.id) {
                return nil
            }
            return FolderNode(folder: folder, children: children.isEmpty ? nil : children)
        }
        return folders.first { $0.parentID == nil }.flatMap(node)
    }
}

public extension FolderNode {
    /// The node with `id` in this subtree.
    func find(_ id: Int64) -> FolderNode? {
        if self.id == id {
            return self
        }
        for child in children ?? [] {
            if let found = child.find(id) {
                return found
            }
        }
        return nil
    }

    /// Nodes from this one down to `id` (for breadcrumbs), or nil if `id` is not in the subtree.
    func path(to id: Int64) -> [FolderNode]? {
        if self.id == id {
            return [self]
        }
        for child in children ?? [] {
            if let path = child.path(to: id) {
                return [self] + path
            }
        }
        return nil
    }
}

public extension Set<MediaKind> {
    /// The kind filter after toggling `kind`; at least one kind always stays on (docs/FEATURES.md §1).
    func toggling(_ kind: MediaKind) -> Set<MediaKind> {
        if contains(kind) {
            return count > 1 ? subtracting([kind]) : self
        }
        return union([kind])
    }
}
