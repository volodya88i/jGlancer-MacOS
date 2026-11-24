import JGModel
import Observation

/// The size map's data (D-127): the folder shown in the main pane and everything below it, with the main pane's
/// filters (kinds, flags, search, hidden folders, small files), as a tree of sizes. Rebuilt off the main thread when
/// the folder or its files change.
@MainActor
@Observable
final class SizeMapModel {
    enum Content: Equatable {
        case loading
        case tree
        /// An album is shown: the map belongs to folders.
        case album
        /// The folder holds no files of the query.
        case empty
    }

    private(set) var tree = SizeTree()
    /// Increments with every new tree.
    private(set) var treeVersion = 0
    private(set) var content = Content.loading
    /// The node under the pointer, from the tree on screen (which may be older than `tree` for a moment).
    var hovered: SizeTree.Node?
    @ObservationIgnored private var loading: Task<Void, Never>?

    /// What the map depends on, to rebuild it only when something changed.
    struct Key: Equatable {
        let folderID: Int64?
        let albumID: Int64?
        let refsVersion: Int
        let treeIDs: [Int64]
    }

    static func key(for library: LibraryModel) -> Key {
        Key(
            folderID: library.state.folderID, albumID: library.state.albumID, refsVersion: library.refsVersion,
            treeIDs: library.state.folderID.flatMap { library.folderNode(id: $0) }.map(ids) ?? []
        )
    }

    private static func ids(_ node: FolderNode) -> [Int64] {
        [node.id] + (node.children ?? []).flatMap(ids)
    }

    func reload(for library: LibraryModel) {
        loading?.cancel()
        guard library.state.albumID == nil, let folderID = library.state.folderID,
              let folder = library.folderNode(id: folderID)
        else {
            tree = SizeTree()
            treeVersion += 1
            content = library.state.albumID != nil ? .album : .empty
            return
        }
        var query = library.query
        query.scope = .folder(id: folderID, includeSubfolders: true)
        let store = library.store
        loading = Task { [weak self] in
            let entries = await (try? store.sizeEntries(for: query)) ?? []
            let tree = await Task.detached(priority: .userInitiated) { SizeTree(folder: folder, files: entries) }.value
            guard let self, !Task.isCancelled else { return }
            hovered = nil
            self.tree = tree
            treeVersion += 1
            content = tree.isEmpty ? .empty : .tree
        }
    }
}

extension LibraryModel {
    /// The sidebar's node of a folder (with its subfolders), if the folder is shown in a tree.
    func folderNode(id: Int64) -> FolderNode? {
        trees.values.lazy.compactMap { $0.find(id) }.first
    }
}
