import AppKit
import JGModel
import JGScanner
import JGStore
import JGThumbs

/// Opening files: from Finder, the Dock, a drop or the Services menu, in the whole app or in the viewer alone.
extension AppModel {
    /// Files and folders from Finder, the Dock or a drop: folders join the library; a photo, video or audio file
    /// opens in its viewer with its folder as context, even outside the library (docs/FEATURES.md §13).
    func open(_ urls: [URL]) async {
        guard !urls.isEmpty else { return }
        if library == nil, isViewerOnly {
            if urls.contains(where: Self.isFolder) {
                // A folder belongs to the library: the whole app from here on.
                isViewerOnly = false
                await ensureLibrary()
            } else {
                await openOnItsOwn(urls)
                return
            }
        }
        guard let library else {
            pendingURLs += urls
            return
        }
        let folders = urls.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
        if !folders.isEmpty {
            viewer = nil
            await library.addFolders(folders)
        }
        guard let file = urls.first(where: { classifier.classify(fileName: $0.lastPathComponent) != nil }),
              let kind = classifier.classify(fileName: file.lastPathComponent)?.kind
        else { return }
        let path = CanonicalPath.of(file)
        let location = try? await library.store.location(of: path, isDirectory: false)
        if let assetID = location?.assetID {
            await openViewer(assetID: assetID)
            return
        }
        await openOutsideFile(path: path, kind: kind, offerFolder: location == nil)
    }

    /// Finder ▸ Services ▸ Quick Preview: the media files among `urls` in Quick Preview over Finder. With one file the
    /// arrows go through the media files of its folder, with several through those. A viewer that is open closes
    /// first (the previews and viewers share one player).
    func quickPreviewFromFinder(_ urls: [URL]) async {
        let files = urls.filter { classifier.classify(fileName: $0.lastPathComponent) != nil }
        guard let first = files.first else {
            NSSound.beep()
            return
        }
        await start()
        // Launched by the service itself: only the panel, no window; quitting when the panel closes (D-69).
        let launchedForThis = isViewerOnly && viewer == nil
        if launchedForThis {
            isViewerOnly = false
            NSApp.windows.first { !($0 is NSPanel) && $0.isVisible }?.orderOut(nil)
        }
        // Quick Preview lives with the library's previews; a viewer opened on its own has none yet.
        await ensureLibrary()
        guard let preview, let quickPreview else { return }
        if viewer != nil {
            closeViewer()
        }
        preview.showExternal(files, index: 0)
        quickPreview.onExternalEnd = launchedForThis ? { NSApp.terminate(nil) } : nil
        quickPreview.openExternal()
        guard files.count == 1 else { return }
        let folder = first.deletingLastPathComponent()
        let siblings = await Task.detached(priority: .userInitiated) {
            (try? FolderListing.files(in: folder, kinds: Set(MediaKind.allCases))) ?? []
        }.value
        preview.replaceExternalFiles(siblings.map { folder.appendingPathComponent($0.name) }, keeping: first)
    }

    /// Viewer-only mode: the file opens with its folder's files around it (as a file outside the library); Add Folder
    /// shows when its folder is not in the library yet.
    func openOnItsOwn(_ urls: [URL]) async {
        guard let file = urls.first(where: { classifier.classify(fileName: $0.lastPathComponent) != nil }),
              let kind = classifier.classify(fileName: file.lastPathComponent)?.kind
        else { return }
        let path = CanonicalPath.of(file)
        let store = try? await openStores().0
        let location = try? await store?.location(of: path, isDirectory: false)
        await openOutsideFile(path: path, kind: kind, offerFolder: location == nil)
    }

    /// Esc in a viewer: leaves segment selection; otherwise back to the library, or, for a viewer opened on its own,
    /// close it (and quit).
    func escapeViewer() {
        // Esc first leaves segment selection (D-73).
        if let mediaViewer, mediaViewer.isSelectingSegment {
            mediaViewer.endSegmentMode()
        } else if isViewerOnly {
            NSApp.terminate(nil)
        } else {
            closeViewer()
        }
    }

    /// Add Folder in a viewer: the library loads if needed (the viewer stays), then the folder joins it.
    func addFolderFromViewer(_ folder: URL) async {
        await ensureLibrary()
        await library?.addFolders([folder])
    }

    /// The databases, opened once: the library with recovery (D-66) and the thumbnail cache; then a daily backup.
    func openStores() async throws -> (LibraryStore, ThumbnailDiskCache) {
        if let stores {
            return stores
        }
        let (library, recovery, cache) = try await Task.detached(priority: .userInitiated) {
            let (library, recovery) = try LibraryStore.openWithRecovery(at: AppPaths.libraryDatabase, backup: AppPaths.libraryBackup)
            return try (library, recovery, ThumbnailDiskCache.open(at: AppPaths.thumbnailCache))
        }.value
        startupRecovery = recovery
        let opened = (library, cache)
        stores = opened
        flagBook.store = library
        // A consistent copy once a day, in the background (restored from if the library is ever damaged).
        Task.detached(priority: .background) {
            try? await library.backup(to: AppPaths.libraryBackup, ifOlderThan: 24 * 60 * 60)
        }
        return opened
    }

    static func isFolder(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    /// Quick Preview's Open in Viewer (W-89): the panel closes and its file opens in the viewer — a library file as
    /// Return would open it, a file from Finder as if Finder opened it. The app comes forward with its window.
    func openFromQuickPreview() {
        guard let quickPreview, let asset = preview?.asset else { return }
        // A service launch quits when its panel closes; opening the viewer keeps the app.
        quickPreview.onExternalEnd = nil
        quickPreview.close()
        NSApp.activate()
        NSApp.windows.first { !($0 is NSPanel) && $0.canBecomeMain }?.makeKeyAndOrderFront(nil)
        Task {
            if asset.id > 0 {
                await openViewer(assetID: asset.id)
            } else {
                await open([asset.url])
            }
        }
    }
}
