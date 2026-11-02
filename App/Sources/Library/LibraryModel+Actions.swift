import Foundation
import JGActions
import JGDesign
import JGModel

/// The library selection as the subject of actions (context menu, menu bar).
extension LibraryModel {
    /// The top bar's star: only flagged files, one flag, or everything (nil).
    func setFlagFilter(_ filter: AssetQuery.FlagFilter?) {
        guard filter != state.flagFilter else { return }
        updateState { $0.flagFilter = filter }
        reloadQuery()
    }

    func setPreviewVisible(_ visible: Bool) {
        updateState { $0.previewVisible = visible }
    }

    func setPreviewWidth(_ width: Double) {
        let clamped = min(max(width, Double(JGMetrics.previewPaneMinWidth)), Double(JGMetrics.previewPaneMaxWidth))
        updateState { $0.previewWidth = clamped.rounded() }
    }

    /// Dragging the sidebar's edge (D-78).
    func setSidebarWidth(_ width: Double) {
        let clamped = min(max(width, Double(JGMetrics.sidebarMinWidth)), Double(JGMetrics.sidebarMaxWidth))
        updateState { $0.sidebarWidth = clamped.rounded() }
    }

    /// Edits the name of `id` in place in the grid.
    func requestInlineRename(_ id: Int64) {
        inlineRenameRequest = (id, (inlineRenameRequest?.serial ?? 0) + 1)
    }

    /// Files were moved, renamed or trashed by the app: views drop their cached rows.
    func filesChanged() {
        rowsVersion += 1
    }

    /// Where a library folder is on disk.
    func url(of folder: Folder) -> URL? {
        guard let root = roots.first(where: { $0.id == folder.rootID }) else { return nil }
        let path = folder.relativePath.isEmpty ? root.path : root.path + "/" + folder.relativePath
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    /// The selected items, kinds and count, without touching the store (menus are built synchronously).
    var actionSelection: ActionSelection {
        let kinds = Set(selection.selected.compactMap { id in
            order.index(of: id).flatMap { refs.indices.contains($0) ? refs[$0].kind : nil }
        })
        return ActionSelection(fileCount: selection.selected.count, kinds: kinds, place: state.albumID == nil ? .library : .album)
    }

    /// The selection as an action target, in display order; paths load from the store when the action runs.
    func actionTarget(sample: URL?) -> ActionTarget? {
        // A folded image sequence stands for all its frames (D-84).
        let ids = expandingSequences(selection.selected.sorted { (order.index(of: $0) ?? .max) < (order.index(of: $1) ?? .max) })
        guard !ids.isEmpty else { return nil }
        let selection = actionSelection
        return ActionTarget(
            place: selection.place, assetIDs: ids, kinds: selection.kinds, count: ids.count, sample: sample,
            urls: { [store] in await ((try? store.assets(ids: ids)) ?? []).map(\.url) }
        )
    }
}
