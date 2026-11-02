import Foundation
import JGModel
import JGStore

/// Virtual albums in the library (docs/FEATURES.md §6): the sidebar list, the album shown in the grid, and the
/// album changes, each undoable through the app's history (`onAlbumChange` registers them).
extension LibraryModel {
    func startAlbums() {
        Task { [weak self] in
            guard let self else { return }
            _ = try? await store.purgeAlbumPlaceholders()
            _ = Task { [weak self] in
                guard let store = self?.store else { return }
                for try await memberships in store.observeAlbumMemberships() {
                    self?.albumMemberships = memberships
                }
            }
            do {
                for try await albums in store.observeAlbums() {
                    self.albums = albums
                    if let id = state.albumID, !albums.contains(where: { $0.id == id }) {
                        leaveAlbum()
                    }
                }
            } catch {}
        }
    }

    /// The album shown in the grid, if any.
    var currentAlbum: Album? {
        state.albumID.flatMap { id in albums.first { $0.id == id } }
    }

    func select(albumID: Int64) {
        guard state.albumID != albumID else { return }
        updateState { $0.albumID = albumID }
        selection.clear()
        reloadQuery()
    }

    func leaveAlbum() {
        updateState { $0.albumID = nil }
        selection.clear()
        reloadQuery()
    }

    // MARK: Changes

    /// A new album, with `assetIDs` if given; returns its id.
    @discardableResult
    func createAlbum(name: String, with assetIDs: [Int64] = []) async -> Int64? {
        guard let album = try? await store.createAlbum(name: name) else { return nil }
        if !assetIDs.isEmpty {
            await addToAlbum(album.id, assetIDs: assetIDs)
        }
        return album.id
    }

    func renameAlbum(_ id: Int64, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        try? await store.renameAlbum(id, to: trimmed)
    }

    /// Deletes the album (never its files).
    func deleteAlbum(_ id: Int64) async {
        try? await store.deleteAlbum(id)
    }

    func addToAlbum(_ albumID: Int64, assetIDs: [Int64]) async {
        guard let added = try? await store.addToAlbum(albumID, assetIDs: assetIDs), !added.isEmpty else { return }
        onAlbumChange?(removal(albumID, added))
    }

    /// Removes items from the album shown; files stay.
    func removeFromCurrentAlbum(_ assetIDs: [Int64]) async {
        guard let albumID = state.albumID,
              let removed = try? await store.removeFromAlbum(albumID, assetIDs: assetIDs), !removed.isEmpty
        else { return }
        selection.clear()
        onAlbumChange?(restoration(albumID, removed))
    }

    func setCover(_ assetID: Int64) async {
        guard let albumID = state.albumID else { return }
        try? await store.setAlbumCover(albumID, assetID: assetID)
    }

    /// Moves items in front of `before` (or to the end) in the album shown.
    func reorderCurrentAlbum(_ assetIDs: [Int64], before: Int64?) async {
        guard let albumID = state.albumID, let old = try? await store.albumOrder(albumID) else { return }
        try? await store.moveInAlbum(albumID, assetIDs: assetIDs, before: before)
        onAlbumChange?(order(albumID, old))
    }

    /// The paths of an album's present items, in album order (Export to Folder).
    func albumURLs(_ albumID: Int64) async -> [URL] {
        let ids = await (try? store.albumOrder(albumID)) ?? []
        return await ((try? store.assets(ids: ids)) ?? []).filter { $0.state == .present }.map(\.url)
    }

    /// Library asset ids of dropped files (others are not in the library and cannot join an album).
    func assetIDs(for urls: [URL]) async -> [Int64] {
        var ids: [Int64] = []
        for url in urls {
            let path = (try? url.resourceValues(forKeys: [.canonicalPathKey]).canonicalPath) ?? url.path
            if let id = try? await store.location(of: path, isDirectory: false)?.assetID {
                ids.append(id)
            }
        }
        return ids
    }

    // MARK: Undo

    private static var addName: String {
        String(localized: "Add to Album", comment: "Action")
    }

    private static var removeName: String {
        String(localized: "Remove from Album", comment: "Action: removes items from the album shown; files stay")
    }

    /// Undoes an add by removing the added items (its inverse puts them back).
    private func removal(_ albumID: Int64, _ ids: [Int64]) -> CustomUndo {
        CustomUndo(name: Self.addName) { [weak self] in
            guard let self, let removed = try? await store.removeFromAlbum(albumID, assetIDs: ids) else { return nil }
            return restoration(albumID, removed, name: Self.addName)
        }
    }

    private func restoration(_ albumID: Int64, _ items: [AlbumItemPosition], name: String = removeName) -> CustomUndo {
        CustomUndo(name: name) { [weak self] in
            guard let self else { return nil }
            try? await store.restoreToAlbum(albumID, items: items)
            return CustomUndo(name: name) { [weak self] in
                guard let self, let removed = try? await store.removeFromAlbum(albumID, assetIDs: items.map(\.assetID))
                else { return nil }
                return restoration(albumID, removed, name: name)
            }
        }
    }

    private func order(_ albumID: Int64, _ old: [Int64]) -> CustomUndo {
        CustomUndo(name: String(localized: "Reorder", comment: "Undo menu: reordering album items")) { [weak self] in
            guard let self, let current = try? await store.albumOrder(albumID) else { return nil }
            try? await store.setAlbumOrder(albumID, old)
            return order(albumID, current)
        }
    }
}
