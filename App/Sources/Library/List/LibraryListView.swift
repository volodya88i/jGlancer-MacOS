import AppKit
import JGModel
import SwiftUI

/// SwiftUI host of the AppKit list (D-125), as `LibraryGridView` hosts the grid: the model's versioned properties read
/// here make SwiftUI call `updateNSView` exactly when they change.
struct LibraryListView: NSViewRepresentable {
    let model: LibraryModel
    let refsVersion: Int
    let selection: AnyHashable
    let rowHeight: Double
    let focusRequest: Int
    let rowsVersion: Int
    let renameSerial: Int
    let sort: AssetQuery.Sort
    let ascending: Bool
    /// The folder shown with its subfolders when they are included; nil for a flat list.
    let shown: FolderNode?
    let insets: NSEdgeInsets

    init(model: LibraryModel, insets: NSEdgeInsets = NSEdgeInsets()) {
        self.model = model
        self.insets = insets
        refsVersion = model.refsVersion
        selection = AnyHashable(model.selection.selected)
        rowHeight = model.state.listRowHeight
        focusRequest = model.focusRequest
        rowsVersion = model.rowsVersion
        renameSerial = model.inlineRenameRequest?.serial ?? 0
        sort = model.state.sort
        ascending = model.state.ascending
        shown = Self.shownFolder(model)
    }

    /// The folder whose subfolders become rows: the one shown, with Include Subfolders on, outside albums and searches
    /// of the whole library.
    @MainActor
    static func shownFolder(_ model: LibraryModel) -> FolderNode? {
        guard model.state.albumID == nil, model.state.includeSubfolders, !(model.searchEverywhere && model.isSearching),
              let id = model.state.folderID
        else { return nil }
        return model.trees.values.lazy.compactMap { $0.find(id) }.first
    }

    func makeCoordinator() -> ListController {
        ListController(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.scrollView
    }

    func updateNSView(_: NSScrollView, context: Context) {
        context.coordinator.setInsets(insets)
        context.coordinator.sync(shown: shown)
    }
}
