import JGDesign
import JGModel

/// The library's query: scope, kind and flag filters, sort, and the view options that go with them.
extension LibraryModel {
    var query: AssetQuery {
        let search = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        var scope: AssetQuery.Scope = state.albumID.map { .album(id: $0) }
            ?? state.folderID.map { .folder(id: $0, includeSubfolders: state.includeSubfolders) } ?? .library
        if !search.isEmpty, searchEverywhere {
            scope = .library
        }
        return AssetQuery(
            scope: scope, kinds: state.kinds, sort: state.sort, ascending: state.ascending, flagFilter: state.flagFilter,
            search: search.isEmpty ? nil : search, hiddenFolders: Set(state.hiddenFolders), minSize: minFileBytes
        )
    }

    /// True while a search narrows the grid.
    var isSearching: Bool {
        !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// New search text: the grid follows after a short pause in typing.
    func setSearch(_ text: String) {
        guard text != searchText else { return }
        searchText = text
        searchTask?.cancel()
        searchTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(JGMetrics.searchDelayMilliseconds))
            guard !Task.isCancelled else { return }
            self?.reloadQuery()
        }
    }

    /// Searches the whole library (on) or the folder or album shown (off).
    func setSearchEverywhere(_ everywhere: Bool) {
        guard everywhere != searchEverywhere else { return }
        searchEverywhere = everywhere
        if isSearching {
            reloadQuery()
        }
    }

    /// Esc in the field: no search, the grid takes the keyboard again.
    func endSearch() {
        searchTask?.cancel()
        let wasSearching = isSearching
        searchText = ""
        if wasSearching {
            reloadQuery()
        }
        focusGrid()
    }

    /// ⌘F.
    func requestSearchFocus() {
        searchFocusRequest += 1
    }

    func select(folderID: Int64) {
        guard state.folderID != folderID || state.albumID != nil else { return }
        updateState {
            $0.folderID = folderID
            $0.albumID = nil
        }
        selection.clear()
        reloadQuery()
    }

    func toggleKind(_ kind: MediaKind) {
        let kinds = state.kinds.toggling(kind)
        guard kinds != state.kinds else { return }
        updateState { $0.kinds = kinds }
        reloadQuery()
    }

    func setSort(_ sort: AssetQuery.Sort) {
        updateState { $0.sort = sort }
        reloadQuery()
    }

    /// A click on a list column's header: the sort and its direction at once (one query).
    func setSort(_ sort: AssetQuery.Sort, ascending: Bool) {
        guard sort != state.sort || ascending != state.ascending else { return }
        updateState {
            $0.sort = sort
            $0.ascending = ascending
        }
        reloadQuery()
    }

    func setAscending(_ ascending: Bool) {
        updateState { $0.ascending = ascending }
        reloadQuery()
    }

    func setIncludeSubfolders(_ include: Bool) {
        updateState { $0.includeSubfolders = include }
        reloadQuery()
    }

    /// Grid or list (D-125).
    func setViewMode(_ mode: LibraryViewState.ViewMode) {
        guard mode != state.viewMode else { return }
        updateState { $0.viewMode = mode }
    }

    func setListRowHeight(_ height: Double) {
        updateState { $0.listRowHeight = height }
    }

    func setTileSide(_ side: Double) {
        updateState { $0.tileSide = side }
    }

    func setShowNames(_ show: Bool) {
        updateState { $0.showNames = show }
    }
}
