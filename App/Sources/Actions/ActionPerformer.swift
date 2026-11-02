import AppKit
import JGActions
import JGModel
import JGStore
import UniformTypeIdentifiers

/// Runs the actions of the registry (docs/ARCHITECTURE.md §15) and names them. Owned by the app model; the
/// context menus and the menu bar both come here.
@MainActor
final class ActionPerformer {
    private weak var appModel: AppModel?
    let openWith: OpenWithStore
    var shortcuts: ShortcutStore? {
        appModel?.shortcuts
    }

    private let info = InfoController()

    /// The registry's features this app has.
    let features: Set<ActionFeature> = [.openWith, .fileOperations, .albums, .flags]

    private var fileOps: FileOperationsModel? {
        appModel?.fileOps
    }

    init(appModel: AppModel, openWith: OpenWithStore) {
        self.appModel = appModel
        self.openWith = openWith
    }

    /// The visible actions for `target`, by section.
    func menu(for target: ActionTarget) -> [[(id: ActionID, isEnabled: Bool)]] {
        let sections = ActionRegistry.menu(for: target.selection, features: features, primaryAppKinds: openWith.settings.kindsWithPrimary)
        guard appModel?.compareModel != nil else { return sections }
        // Compare runs four actions only (W-77).
        return sections.map { $0.filter { AppModel.compareActions.contains($0.id) } }.filter { !$0.isEmpty }
    }

    func perform(_ id: ActionID, on target: ActionTarget) {
        if appModel?.compareModel != nil, !AppModel.compareActions.contains(id) {
            return
        }
        Task {
            switch id {
            case .splitStems:
                await appModel?.requestStemSplit(target)
            case .open, .quickPreview, .playInMiniPlayer, .compare:
                await performOpening(id, on: target)
            case .editInPrimaryApp:
                if let kind = target.kind, let app = openWith.settings.primary(for: kind) {
                    if let url = OpenWithStore.location(of: app) {
                        await open(target, with: url)
                    } else {
                        NSSound.beep()
                    }
                }
            case .getInfo, .revealInFinder, .copyPath, .copy:
                await performFileAction(id, on: target)
            case .moveTo, .copyTo, .rename, .moveToTrash:
                await performFileOperation(id, on: target)
            case .removeFromAlbum, .setAlbumCover:
                await performAlbumAction(id, on: target)
            case .openWith, .addToAlbum, .flag:
                // Submenus: their items do the work.
                break
            }
        }
    }

    private func performAlbumAction(_ id: ActionID, on target: ActionTarget) async {
        guard let library = appModel?.activeLibrary else { return }
        if id == .removeFromAlbum {
            await library.removeFromCurrentAlbum(target.assetIDs)
        } else if let first = target.assetIDs.first {
            await library.setCover(first)
        }
    }

    /// Move to…, Copy to…, Rename…, Move to Trash.
    private func performFileOperation(_ id: ActionID, on target: ActionTarget) async {
        switch id {
        case .moveTo, .copyTo:
            await transfer(target, to: nil, copying: id == .copyTo)
        case .rename:
            // Several files: a pattern. One in the library: the name is edited on the tile, like Finder;
            // elsewhere in a small sheet.
            if target.count > 1 {
                await requestBatchRename(target)
            } else if target.place != .viewer, let id = target.assetIDs.first, let library = appModel?.activeLibrary {
                library.requestInlineRename(id)
            } else if let url = await target.urls().first {
                fileOps?.requestRename(url)
            }
        case .moveToTrash:
            await fileOps?.trash(target.urls())
            if target.place == .viewer {
                appModel?.viewerRemovedCurrentFile()
            }
        default:
            break
        }
    }

    /// Open, Quick Preview, Play in Mini Player.
    private func performOpening(_ id: ActionID, on target: ActionTarget) async {
        switch id {
        case .open:
            if target.place == .library, let first = target.assetIDs.first {
                appModel?.activeLibrary?.open(first)
            }
        case .quickPreview:
            appModel?.quickPreview?.toggle(over: NSApp.mainWindow)
        case .playInMiniPlayer:
            if target.place == .viewer {
                appModel?.continueInMiniPlayer()
            } else {
                await appModel?.playInMiniPlayer(target.assetIDs)
            }
        case .compare:
            await appModel?.openCompare(target.assetIDs)
        default:
            break
        }
    }

    /// Get Info, Reveal in Finder and the clipboard.
    private func performFileAction(_ id: ActionID, on target: ActionTarget) async {
        switch id {
        case .getInfo:
            await info.show(target, store: appModel?.activeLibrary?.store)
        case .revealInFinder:
            await NSWorkspace.shared.activateFileViewerSelecting(target.urls())
        case .copyPath:
            let paths = await target.urls().map(\.path).joined(separator: "\n")
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(paths, forType: .string)
        case .copy:
            let urls = await target.urls()
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects(urls.map { $0 as NSURL })
        default:
            break
        }
    }

    /// Move to… / Copy to… into `folder` (nil: choose one).
    func transfer(_ target: ActionTarget, to folder: URL?, copying: Bool) async {
        await fileOps?.transfer(target.urls(), to: folder, copying: copying)
    }

    /// Opens the files with an app (Open With, Edit in …).
    func open(_ target: ActionTarget, with app: URL) async {
        let urls = await target.urls()
        guard !urls.isEmpty else { return }
        _ = try? await NSWorkspace.shared.open(urls, withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
    }

    /// Open With → Other…: any app, chosen in a panel.
    func openWithOtherApp(_ target: ActionTarget) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        panel.prompt = String(localized: "Open", comment: "Action: open the file")
        guard panel.runModal() == .OK, let app = panel.url else { return }
        Task { await open(target, with: app) }
    }

    // MARK: Titles

    /// Albums for the Add to Album submenu (the one shown is left out), with how many of `target`'s files each
    /// already holds.
    func albumsForAdding(_ target: ActionTarget) -> [AlbumChoice] {
        guard let library = appModel?.activeLibrary else { return [] }
        return library.albums.filter { $0.id != library.state.albumID }.map { album in
            let contained = target.assetIDs.filter { library.albumMemberships[$0]?.contains(album.id) == true }.count
            return AlbumChoice(id: album.id, name: album.name, contained: contained)
        }
    }

    func add(_ target: ActionTarget, toAlbum albumID: Int64) {
        Task { await appModel?.activeLibrary?.addToAlbum(albumID, assetIDs: target.assetIDs) }
    }

    /// New Album… from a selection: the album is created with the files and its name is edited in the sidebar.
    func addToNewAlbum(_ target: ActionTarget) {
        Task {
            guard let library = appModel?.activeLibrary else { return }
            let name = String(localized: "New Album", comment: "Default name of a new album")
            if let id = await library.createAlbum(name: name, with: target.assetIDs) {
                library.renamingAlbumID = id
            }
        }
    }

    var recentFolders: [URL] {
        fileOps?.recentFolders ?? []
    }

    func title(for id: ActionID, target: ActionTarget) -> String {
        switch id {
        case .open: String(localized: "Open", comment: "Action: open the file")
        case .quickPreview: String(localized: "Quick Preview", comment: "Accessibility label of the Quick Preview window")
        case .playInMiniPlayer, .compare, .splitStems: openingTitle(for: id)
        case .openWith: String(localized: "Open With", comment: "Menu of other apps that can open the file")
        case .editInPrimaryApp: editTitle(target)
        case .getInfo: String(localized: "Get Info", comment: "Action")
        case .revealInFinder: String(localized: "Reveal in Finder")
        case .copyPath: String(localized: "Copy Path", comment: "Action: copies the file paths as text")
        case .copy: String(localized: "Copy", comment: "Action: copies the files")
        default: laterTitle(for: id)
        }
    }

    /// Titles of the album, flag and file operation actions.
    private func laterTitle(for id: ActionID) -> String {
        switch id {
        case .addToAlbum, .removeFromAlbum, .setAlbumCover: albumTitle(for: id)
        case .flag: String(localized: "Flag", comment: "Menu of flag colors")
        case .moveTo: String(localized: "Move to…", comment: "Action")
        case .copyTo: String(localized: "Copy to…", comment: "Action")
        case .rename: String(localized: "Rename…", comment: "Action")
        case .moveToTrash: String(localized: "Move to Trash", comment: "Action")
        default: ""
        }
    }

    private func openingTitle(for id: ActionID) -> String {
        switch id {
        case .compare: String(localized: "Compare", comment: "Action: two photos side by side")
        case .splitStems: String(localized: "Split into Stems…", comment: "Action: separates a song into vocals, drums, bass…")
        default: String(localized: "Play in Mini Player", comment: "Action: songs play in the bar at the bottom")
        }
    }

    private func albumTitle(for id: ActionID) -> String {
        switch id {
        case .removeFromAlbum: String(localized: "Remove from Album", comment: "Action: removes items from the album shown; files stay")
        case .setAlbumCover: String(localized: "Use as Album Cover", comment: "Action")
        default: String(localized: "Add to Album", comment: "Action")
        }
    }

    private func editTitle(_ target: ActionTarget) -> String {
        let name = target.kind.flatMap { openWith.settings.primary(for: $0)?.name } ?? ""
        return String(localized: "Edit in \(name)", comment: "Action: opens the files in the primary external app")
    }
}

/// An album in the Add to Album submenu and how many of the selected files it already holds.
struct AlbumChoice {
    let id: Int64
    let name: String
    let contained: Int
}

// MARK: Flags

extension ActionPerformer {
    /// ⌃F, ⌃1–⌃6, ⌃0 and the Flag menus: pressing a flag every file already has removes it (D-57). Undoable.
    func setFlag(_ pressed: AssetFlag, on target: ActionTarget) {
        guard let appModel, appModel.compareModel == nil, let store = appModel.library?.store, !target.assetIDs.isEmpty else {
            NSSound.beep()
            return
        }
        let ids = target.assetIDs
        Task {
            let current = await (try? store.flags(ids: ids)) ?? [:]
            let flag = AssetFlag.applying(pressed, to: ids.map { current[$0] ?? .none })
            guard let previous = try? await store.setFlag(flag, assetIDs: ids) else { return }
            appModel.flagsChanged()
            appModel.fileOps?.register(flagUndo(store: store, restoring: previous))
        }
    }

    /// Puts `flags` back; running it returns the change that redoes what it undid.
    private func flagUndo(store: LibraryStore, restoring flags: [Int64: AssetFlag]) -> CustomUndo {
        CustomUndo(name: String(localized: "Flag", comment: "Menu of flag colors")) { [weak self] in
            let now = await (try? store.flags(ids: Array(flags.keys))) ?? [:]
            try? await store.restoreFlags(flags)
            self?.appModel?.flagsChanged()
            return self?.flagUndo(store: store, restoring: now)
        }
    }
}

// MARK: Batch rename

extension ActionPerformer {
    /// Opens the pattern sheet for the files of `target`, each with its capture date (else modification date).
    func requestBatchRename(_ target: ActionTarget) async {
        guard let appModel, let fileOps = appModel.fileOps else { return }
        let assets = await (try? appModel.library?.store.assets(ids: target.assetIDs)) ?? []
        let files = assets.map { BatchRenamePattern.File(url: $0.url, date: $0.capturedAt ?? $0.modifiedAt) }
        guard files.count > 1 else { return }
        fileOps.batchRenameRequest = .init(files: files)
    }
}
