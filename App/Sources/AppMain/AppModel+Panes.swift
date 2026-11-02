import AppKit
import JGModel

/// Wiring of the library panes: the main one and a split view's second one (D-89).
extension AppModel {
    /// Wires a pane (the main one, or a split view's second one): opening, actions, menus, and — while it is the
    /// active pane — the preview and Quick Preview (D-89).
    func connectPane(_ pane: LibraryModel) {
        pane.onOpenAsset = { [weak self, weak pane] id in
            guard let self, let pane else { return }
            activate(pane)
            Task { await self.openViewer(assetID: id) }
        }
        connectActions(to: pane)
        pane.onSelectionChange = { [weak self, weak pane] selection in
            guard let self, let pane else { return }
            activate(pane)
            preview?.selectionChanged(selection)
        }
        pane.onSequenceToggle = { [weak self] in self?.preview?.reload() }
        pane.onInteraction = { [weak self, weak pane] in
            pane.map { self?.activate($0) }
        }
        pane.performAction = { [weak self, weak pane] id in
            guard let self, let target = pane?.actionTarget(sample: preview?.asset?.url) else { return }
            actions.perform(id, on: target)
        }
        pane.onQuickPreviewKey = { [weak self] key in
            guard let quickPreview = self?.quickPreview, let preview = self?.preview else { return false }
            return Self.handle(key, quickPreview: quickPreview, preview: preview)
        }
    }

    /// Space toggles Quick Preview, Esc closes it, Return pauses, F toggles full screen (Space and Esc leave full
    /// screen first); false when the key is not for Quick Preview.
    private static func handle(_ key: LibraryModel.QuickPreviewKey, quickPreview: QuickPreviewController, preview: PreviewModel) -> Bool {
        switch key {
        case .space:
            if quickPreview.isFullScreen {
                quickPreview.toggleFullScreen()
            } else {
                quickPreview.toggle(over: NSApp.mainWindow)
            }
            return true
        case .escape:
            guard quickPreview.isOpen else { return false }
            if quickPreview.isFullScreen {
                quickPreview.toggleFullScreen()
            } else {
                quickPreview.close()
            }
            return true
        case .returnKey:
            guard quickPreview.isOpen else { return false }
            preview.togglePlayPause()
            return true
        case .fullScreen:
            guard quickPreview.isOpen else { return false }
            quickPreview.toggleFullScreen()
            return true
        }
    }

    /// Context menus, in-place rename, the sidebar Trash and folder drops.
    private func connectActions(to library: LibraryModel) {
        library.makeContextMenu = { [weak self] target in
            self.flatMap { ActionMenu.make(for: target, performer: $0.actions) }
        }
        library.onInlineRename = { [weak self] url, name in
            guard let fileOps = self?.fileOps else { return }
            Task {
                if let problem = await fileOps.rename(url, to: name) {
                    NSSound.beep()
                    fileOps.showMessage(problem)
                }
            }
        }
        library.onExportAlbum = { [weak self, weak library] albumID in
            guard let library else { return }
            Task {
                let urls = await library.albumURLs(albumID)
                self?.fileOps?.transfer(urls, to: nil, copying: true)
            }
        }
        library.onAlbumChange = { [weak self] change in
            self?.fileOps?.register(change)
        }
        library.onTrashFiles = { [weak self] urls in
            self?.fileOps?.trash(urls)
        }
        library.onPlayInMiniPlayer = { [weak self] id in
            Task { await self?.playInMiniPlayer([id]) }
        }
        library.onCreateFolder = { [weak self] parent, name in
            self?.fileOps?.createFolder(named: name, in: parent)
        }
        library.onDropFiles = { [weak self] urls, folder, copying in
            self?.fileOps?.transfer(urls, to: folder, copying: copying)
        }
    }
}
