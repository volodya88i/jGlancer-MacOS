import Foundation
import JGModel
import JGPlayback
import JGScanner
import JGStore

/// Building the viewers: the folder context of a library asset or of a file from outside the library.
extension AppModel {
    /// Opens the viewer of a library asset. It pages through the files of its kind that the grid shows — the folder
    /// (with subfolders only while Include Subfolders is on) or the album, with the flag filter — in the library's
    /// sort (D-09, D-78). A search result, or a file not in the grid (opened from Finder over an album), pages
    /// through its own folder.
    func openViewer(assetID: Int64) async {
        guard let library = activeLibrary, let asset = try? await library.store.assets(ids: [assetID]).first else { return }
        let own = AssetQuery(
            scope: .folder(id: asset.folderID, includeSubfolders: false), kinds: [asset.kind],
            sort: library.state.sort, ascending: library.state.ascending
        )
        var refs: [AssetRef] = []
        if !library.isSearching {
            refs = await (try? library.store.assetRefs(for: Self.pagingQuery(library, kind: asset.kind))) ?? []
        }
        if !refs.contains(where: { $0.id == assetID }) {
            refs = await (try? library.store.assetRefs(for: own)) ?? [AssetRef(id: assetID, kind: asset.kind)]
        }
        switch asset.kind {
        case .photo:
            viewer = .photo(PhotoViewerModel(
                entries: refs.map { .asset($0.id) },
                index: refs.firstIndex { $0.id == assetID } ?? 0,
                store: library.store, thumbnails: library.thumbnails, screenPixels: Self.screenPixels,
                opened: ViewerPhoto(
                    url: asset.url, name: asset.name, assetID: asset.id, modifiedAt: asset.modifiedAt,
                    typeIdentifier: asset.typeIdentifier
                ),
                decodeGate: library.indexer.pause
            ))
        case .video, .audio:
            let assets = await (try? library.store.assets(ids: refs.map(\.id))) ?? []
            let items = (assets.isEmpty ? [asset] : assets).map(PlaybackItem.init(asset:))
            let queue = PlaybackQueue(items: items, index: items.firstIndex { $0.assetID == assetID } ?? 0)
            let model = MediaViewerModel(
                kind: asset.kind, queue: queue, playback: playback, thumbnails: library.thumbnails,
                waveforms: waveforms, tuning: tuning, segmentKeepsAudioFormat: settingsStore.settings.segmentKeepsAudioFormat
            )
            model.showMessage = { [weak self] in self?.fileOps?.showMessage($0) }
            viewer = .media(model)
        }
    }

    /// The grid's query narrowed to one kind: what the viewer pages through.
    private static func pagingQuery(_ library: LibraryModel, kind: MediaKind) -> AssetQuery {
        let shown = library.query
        return AssetQuery(
            scope: shown.scope, kinds: [kind], sort: shown.sort, ascending: shown.ascending, flagFilter: shown.flagFilter
        )
    }

    /// Shows the file at once, then lists its folder in the background for previous / next.
    func openOutsideFile(path: String, kind: MediaKind, offerFolder: Bool) async {
        let folder = (path as NSString).deletingLastPathComponent
        let name = (path as NSString).lastPathComponent
        let url = URL(fileURLWithPath: path)
        let modifiedAt = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
        let typeIdentifier = classifier.classify(fileName: name)?.typeIdentifier
        let folderToOffer = offerFolder ? URL(fileURLWithPath: folder, isDirectory: true) : nil
        let show: ([ScannedFile]) -> Void
        switch kind {
        case .photo:
            let opened = ViewerPhoto(url: url, name: name, assetID: nil, modifiedAt: modifiedAt, typeIdentifier: typeIdentifier)
            let model = PhotoViewerModel(
                entries: [.file(opened)], index: 0, store: nil, thumbnails: nil, screenPixels: Self.screenPixels,
                folderToOffer: folderToOffer
            )
            viewer = .photo(model)
            show = { [weak self] files in
                guard self?.photoViewer === model else { return }
                model.replaceEntries(files.map { file in
                    .file(ViewerPhoto(
                        url: URL(fileURLWithPath: folder + "/" + file.name), name: file.name, assetID: nil,
                        modifiedAt: file.modifiedAt, typeIdentifier: file.typeIdentifier
                    ))
                }, keeping: url)
            }
        case .video, .audio:
            let item = PlaybackItem(url: url, name: name, kind: kind, modifiedAt: modifiedAt, typeIdentifier: typeIdentifier)
            let model = MediaViewerModel(
                kind: kind, queue: PlaybackQueue(items: [item]), playback: playback, thumbnails: nil,
                waveforms: waveforms, tuning: tuning, folderToOffer: folderToOffer,
                segmentKeepsAudioFormat: settingsStore.settings.segmentKeepsAudioFormat
            )
            model.showMessage = { [weak self] in self?.fileOps?.showMessage($0) }
            viewer = .media(model)
            show = { [weak self] files in
                guard self?.mediaViewer === model else { return }
                model.replaceItems(files.map { file in
                    PlaybackItem(
                        url: URL(fileURLWithPath: folder + "/" + file.name), name: file.name, kind: file.kind,
                        modifiedAt: file.modifiedAt, typeIdentifier: file.typeIdentifier
                    )
                })
            }
        }
        let files = await Task.detached(priority: .userInitiated) {
            (try? FolderListing.files(in: URL(fileURLWithPath: folder, isDirectory: true), kinds: [kind])) ?? []
        }.value
        if !files.isEmpty {
            show(files)
        }
    }
}
