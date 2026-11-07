/// The rows of the library's list view (D-125), as Finder lists a folder: the files of the folder shown and, when
/// subfolders are included, a row for each subfolder that holds files of the query (in it or below), which unfolds to
/// its own subfolders and files. Files keep the query's order (its sort and filters); folders come first in natural
/// name order, reversed by a descending sort. Albums, searches of the whole library and a folder without its
/// subfolders are flat lists.
public struct ListOutline: Equatable, Sendable {
    public enum Row: Hashable, Sendable {
        case folder(Int64)
        case asset(Int64)
    }

    /// Rows of each folder row (by folder id) and of the top level (nil).
    private let rows: [Int64?: [Row]]
    /// The folder of every folder row.
    public let folders: [Int64: Folder]
    /// The folder row each nested file sits in.
    private let assetFolders: [Int64: Int64]
    /// The parent of every folder row, nil at the top level.
    private let folderParents: [Int64: Int64?]

    /// An empty list.
    public init() {
        rows = [:]
        folders = [:]
        assetFolders = [:]
        folderParents = [:]
    }

    /// - Parameters:
    ///   - refs: the files of the query, in its order.
    ///   - shown: the folder shown with its subfolders (the sidebar's tree), nil for a flat list.
    ///   - foldersDescending: folders in reverse name order (a descending sort).
    public init(refs: [AssetRef], shown: FolderNode?, foldersDescending: Bool = false) {
        guard let shown else {
            rows = [nil: refs.map { .asset($0.id) }]
            folders = [:]
            assetFolders = [:]
            folderParents = [:]
            return
        }
        // Every folder below the one shown, with its parent (nil for the shown folder's own subfolders).
        var parents: [Int64: Int64?] = [:]
        var byID: [Int64: Folder] = [:]
        var ordered: [FolderNode] = []
        func collect(_ node: FolderNode, parent: Int64?) {
            for child in node.children ?? [] {
                parents[child.id] = parent
                byID[child.id] = child.folder
                ordered.append(child)
                collect(child, parent: child.id)
            }
        }
        collect(shown, parent: nil)
        var rows: [Int64?: [Row]] = [:]
        var used = Set<Int64>()
        var assetFolders: [Int64: Int64] = [:]
        for ref in refs {
            guard ref.folderID != shown.id, parents[ref.folderID] != nil else {
                // In the folder shown (or in one the tree does not know yet): a top-level row.
                rows[nil, default: []].append(.asset(ref.id))
                continue
            }
            rows[ref.folderID, default: []].append(.asset(ref.id))
            assetFolders[ref.id] = ref.folderID
            var folder: Int64? = ref.folderID
            while let current = folder, used.insert(current).inserted {
                folder = parents[current] ?? nil
            }
        }
        // Folders first, in the tree's natural order (each parent's children are already sorted).
        let shownFolders = (foldersDescending ? ordered.reversed() : ordered).filter { used.contains($0.id) }
        var folderRows: [Int64?: [Row]] = [:]
        for node in shownFolders {
            folderRows[parents[node.id] ?? nil, default: []].append(.folder(node.id))
        }
        for (parent, folderList) in folderRows {
            rows[parent] = folderList + (rows[parent] ?? [])
        }
        self.rows = rows
        folders = byID.filter { used.contains($0.key) }
        self.assetFolders = assetFolders
        folderParents = parents.filter { used.contains($0.key) }
    }

    /// The rows inside a folder row, or the top level for nil.
    public func children(of folder: Int64?) -> [Row] {
        rows[folder] ?? []
    }

    /// The folder rows from the top level down to the one holding `assetID`; empty for a top-level file.
    public func folderPath(toAsset assetID: Int64) -> [Int64] {
        var path: [Int64] = []
        var folder = assetFolders[assetID]
        while let current = folder {
            path.insert(current, at: 0)
            folder = folderParents[current] ?? nil
        }
        return path
    }
}
