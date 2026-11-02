import AppKit
import JGModel
import JGScanner
import JGStore

/// Folder commands of the sidebar (D-86, W-52): New Folder…, Show in Finder, Move to Trash.
extension LibraryModel {
    /// The sidebar tree of `root`: folders with media below them, plus folders made in this session.
    func folderTree(_ listing: FolderContents, root: RootFolder) -> FolderNode? {
        let created = listing.folders.filter { folder in
            createdFolders.contains(folder.relativePath.isEmpty ? root.path : root.path + "/" + folder.relativePath)
        }
        return FolderNode.tree(from: listing.folders, withMedia: listing.withMedia.union(created.map(\.id)))
    }

    /// Asks for a name (a free one next to the taken ones is offered) and makes the folder through the undoable
    /// file operations; it shows in the sidebar while empty.
    func newFolder(in folder: Folder) {
        guard let parent = url(of: folder), let name = Self.askFolderName(suggested: Self.freeFolderName(in: parent)) else { return }
        createdFolders.insert(CanonicalPath.of(parent.appendingPathComponent(name)))
        expandedFolders.insert(folder.id)
        onCreateFolder?(parent, name)
        refreshTrees()
    }

    func showInFinder(_ folder: Folder) {
        guard let url = url(of: folder) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    /// A subfolder (never a root) and everything in it to the Trash, undoably.
    func trash(_ folder: Folder) {
        guard folder.parentID != nil, let url = url(of: folder) else { return }
        onTrashFiles?([url])
    }

    /// Rebuilds the trees from the last listings (after `createdFolders` changed).
    func refreshTrees() {
        for root in roots {
            if let listing = listings[root.id] {
                trees[root.id] = folderTree(listing, root: root)
            }
        }
    }

    /// "New Folder", or "New Folder 2", "New Folder 3"… when taken.
    static func freeFolderName(in parent: URL) -> String {
        let base = String(localized: "New Folder", comment: "Undo menu: the operation to undo")
        var name = base
        var number = 2
        while FileManager.default.fileExists(atPath: parent.appendingPathComponent(name).path) {
            name = "\(base) \(number)"
            number += 1
        }
        return name
    }

    private static func askFolderName(suggested: String) -> String? {
        let alert = NSAlert()
        alert.messageText = String(localized: "New Folder", comment: "Undo menu: the operation to undo")
        let field = NSTextField(string: suggested)
        field.frame = NSRect(x: 0, y: 0, width: 260, height: 24)
        alert.accessoryView = field
        alert.addButton(withTitle: String(localized: "Create", comment: "Alert button: makes the new folder"))
        alert.addButton(withTitle: String(localized: "Cancel", comment: "Alert button"))
        alert.window.initialFirstResponder = field
        guard alert.runModal() == .alertFirstButtonReturn else { return nil }
        let name = field.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || name.contains("/") || name.contains(":") || name.hasPrefix(".") ? nil : name
    }
}

/// Roots and folder lookup.
extension LibraryModel {
    // MARK: Roots

    /// Adds folders chosen in a panel or dropped on the window.
    func addFolders(_ urls: [URL]) async {
        for url in urls {
            // A whole drive can hold far more than photos: ask first (D-85).
            if (try? url.resourceValues(forKeys: [.isVolumeKey]))?.isVolume == true, !Self.confirmWholeDrive(url) {
                continue
            }
            pendingAdds.insert(CanonicalPath.of(url))
            do {
                let root = try await scanner.registerRoot(at: url)
                if let top = try await store.folders(rootID: root.id).first?.id {
                    select(folderID: top)
                }
            } catch StoreError.rootAlreadyExists {
                problem = .alreadyInLibrary
            } catch StoreError.rootOverlapsExisting {
                problem = .overlapsLibraryFolder
            } catch {
                problem = .folderUnavailable
            }
        }
    }

    /// Removes a root from the library. Files on disk are never touched.
    func removeRoot(_ id: Int64) async {
        indexer.stopWatching(id)
        try? await store.removeRoot(id: id)
    }

    // MARK: Lookup

    func folder(id: Int64) -> Folder? {
        trees.values.lazy.compactMap { $0.find(id)?.folder }.first
    }

    /// Folders from the root down to `id`, for the breadcrumb.
    func path(to id: Int64) -> [Folder] {
        trees.values.lazy.compactMap { $0.path(to: id) }.first?.map(\.folder) ?? []
    }
}
