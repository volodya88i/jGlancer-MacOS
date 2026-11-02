import Foundation
import JGModel

/// Pinned folders (D-87, W-76): any folder can be pinned to the top of the sidebar; pins are saved by path in the
/// view state, and a folder that is missing (an unplugged drive) is skipped until it comes back.
extension LibraryModel {
    /// The pinned folders that exist now, in pin order, with their paths.
    var pinnedFolders: [(folder: Folder, path: String)] {
        var byPath: [String: Folder] = [:]
        for root in roots {
            guard let tree = trees[root.id] else { continue }
            var stack = [tree]
            while let node = stack.popLast() {
                if let url = url(of: node.folder) {
                    byPath[url.path] = node.folder
                }
                stack += node.children ?? []
            }
        }
        return state.pinnedFolders.compactMap { path in byPath[path].map { ($0, path) } }
    }

    func isPinned(_ folder: Folder) -> Bool {
        url(of: folder).map { state.pinnedFolders.contains($0.path) } ?? false
    }

    func pin(_ folder: Folder) {
        guard let path = url(of: folder)?.path, !state.pinnedFolders.contains(path) else { return }
        updateState { $0.pinnedFolders.append(path) }
    }

    func unpin(_ folder: Folder) {
        guard let path = url(of: folder)?.path else { return }
        updateState { $0.pinnedFolders.removeAll { $0 == path } }
    }

    /// Shows a pinned folder and expands its parents in the tree.
    func showPinned(_ folder: Folder, in pane: LibraryModel? = nil) {
        for parent in path(to: folder.id).dropLast() {
            expandedFolders.insert(parent.id)
        }
        (pane ?? self).select(folderID: folder.id)
    }
}
