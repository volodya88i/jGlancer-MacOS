import JGDesign
import JGModel
import JGSettings
import SwiftUI

@main
struct JGlancerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private var appModel: AppModel {
        appDelegate.appModel
    }

    var body: some Scene {
        Window(Text(verbatim: AppIdentity.name), id: SceneID.main) {
            MainView(appModel: appModel)
                .appSettings(appModel.settingsStore)
                .environment(\.flagBook, appModel.flagBook)
                // The window's buttons centred on the top bar (D-114).
                .background(WindowControlsInstaller().frame(width: 0, height: 0))
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: JGMetrics.windowDefaultWidth, height: JGMetrics.windowDefaultHeight)
        .commands {
            LibraryCommands(appModel: appModel)
            UndoCommands(appModel: appModel)
        }

        Window(Text("Find Duplicates", comment: "Window title"), id: SceneID.duplicates) {
            DuplicatesView(appModel: appModel)
                .appSettings(appModel.settingsStore)
        }
        .defaultSize(width: JGMetrics.duplicatesWidth, height: JGMetrics.duplicatesHeight)

        Settings {
            SettingsView(appModel: appModel)
                .appSettings(appModel.settingsStore)
        }

        #if DEBUG
            // Developer tool: every design token, dark and light side by side (Window ▸ Design Gallery).
            Window(Text(verbatim: "Design Gallery"), id: SceneID.designGallery) {
                JGDesignGallery()
                    .frame(minWidth: JGMetrics.windowMinWidth, minHeight: JGMetrics.windowMinHeight)
            }
            .defaultSize(width: JGMetrics.windowDefaultWidth, height: JGMetrics.windowDefaultHeight)
        #endif
    }
}

/// Identifiers of the app's scenes.
enum SceneID {
    static let main = "main"
    static let duplicates = "duplicates"
    static let designGallery = "design-gallery"
}

/// The main window's root: the library once the databases are open.
struct MainView: View {
    /// The library's size while no viewer covers it: under a viewer it keeps it, so resizing the window lays out
    /// only the viewer (D-112).
    @State private var librarySize: CGSize?
    let appModel: AppModel

    private func libraryView(_ library: LibraryModel) -> some View {
        LibraryView(
            model: library, preview: appModel.preview, onOpen: { urls in Task { await appModel.open(urls) } },
            miniPlayer: appModel.windowPlayer, onShowMiniPlayerSong: appModel.showInLibrary,
            secondPane: appModel.secondPane, isSecondPaneActive: appModel.isSecondPaneActive,
            onSplitFraction: appModel.setSplitFraction
        )
        .frame(width: frozenLibrarySize?.width, height: frozenLibrarySize?.height)
        .onGeometryChange(for: CGSize.self) { $0.size } action: { size in
            if appModel.viewer == nil {
                librarySize = size
            }
        }
    }

    /// Settings → Effects → See through the photo viewer, while a photo is open.
    private var seesThroughPhotoViewer: Bool {
        guard case .photo = appModel.viewer else { return false }
        return appModel.settingsStore.settings.translucentPhotoViewer && !NSWorkspace.shared.accessibilityDisplayShouldReduceTransparency
    }

    /// The library's own size under a viewer; nil (the window's) without one.
    private var frozenLibrarySize: CGSize? {
        appModel.viewer == nil ? nil : librarySize
    }

    private func addFolder(_ folder: URL) {
        Task { await appModel.addFolderFromViewer(folder) }
    }

    var body: some View {
        ZStack {
            if let error = appModel.startupError {
                StartupErrorView(detail: error)
            } else if appModel.isViewerOnly {
                // Opened for a file: no library behind the viewer (it loads on "‹ Library").
                Rectangle().fill(JGColor.bgMedia)
            } else if !appModel.settingsStore.settings.hasChosenAppearance {
                // First launch: the choice of a look in place of the library, sized by the window alone.
                OnboardingView(store: appModel.settingsStore)
            } else if let library = appModel.library {
                // The library stays underneath the viewer, so its scroll position and state survive. It hangs in a
                // window-sized frame: kept at its size under a viewer, it must never make the stack (and the viewer
                // over it) bigger than the window (D-115).
                Color.clear
                    .overlay(alignment: .topLeading) { libraryView(library) }
                    // A see-through photo viewer shows the desktop, not the library (D-114).
                    .opacity(seesThroughPhotoViewer ? 0 : 1)
                    .allowsHitTesting(appModel.viewer == nil)
                    .accessibilityHidden(appModel.viewer != nil)
            } else {
                Rectangle().fill(JGColor.bgBase)
            }
            switch appModel.viewer {
            case let .photo(model):
                PhotoViewerView(
                    model: model, onClose: appModel.closeViewer, onEscape: appModel.escapeViewer, onAddFolder: addFolder,
                    contextMenu: appModel.viewerContextMenu
                )
                .modifier(ViewerFileDrop(appModel: appModel))
            case let .media(model):
                MediaViewerView(
                    model: model, onClose: appModel.leaveMediaViewer, onEscape: appModel.escapeViewer, onAddFolder: addFolder,
                    contextMenu: appModel.viewerContextMenu
                )
                .id(ObjectIdentifier(model))
                .modifier(ViewerFileDrop(appModel: appModel))
            case let .compare(model):
                CompareView(
                    model: model, onClose: appModel.closeViewer, onInfo: appModel.compareInfo,
                    contextMenu: appModel.compareContextMenu(side:)
                )
            case nil:
                EmptyView()
            }
        }
        .background(WindowSeeThrough(isOn: seesThroughPhotoViewer).frame(width: 0, height: 0))
        .overlay(alignment: .top) {
            if let recovery = appModel.startupRecovery {
                RecoveryBanner(recovery: recovery) { appModel.startupRecovery = nil }
                    .padding(.top, JGMetrics.barHeight + JGSpacing.s)
            }
        }
        .overlay(alignment: .bottom) {
            if let fileOps = appModel.fileOps, let toast = fileOps.toast {
                JGToast(
                    Text(verbatim: toast.message),
                    actionTitle: toast.canUndo ? Text("Undo", comment: "Toast: undoes the file operation")
                        : toast.reveal != nil ? Text("Show in Finder", comment: "Sidebar folder menu") : nil,
                    action: toast.canUndo ? { fileOps.undo() }
                        : toast.reveal.map { url in { NSWorkspace.shared.activateFileViewerSelecting([url]) } },
                    progress: toast.progress,
                    stop: toast.progress != nil
                        ? (Text("Stop", comment: "Toast: stops a running file operation"), { fileOps.stop() })
                        : nil
                )
                .padding(.bottom, JGSpacing.xl)
                .transition(.opacity)
                .id(toast.id)
            }
        }
        .sheet(item: Binding(get: { appModel.fileOps?.renameRequest }, set: { appModel.fileOps?.renameRequest = $0 })) { request in
            if let fileOps = appModel.fileOps {
                RenameSheet(fileOps: fileOps, url: request.url)
            }
        }
        .sheet(item: Binding(get: { appModel.updates.offer }, set: { appModel.updates.offer = $0 })) { offer in
            UpdateSheet(updates: appModel.updates, offer: offer)
        }
        .sheet(item: Binding(get: { appModel.stems.request }, set: { appModel.stems.request = $0 })) { request in
            StemSplitSheet(stems: appModel.stems, songs: request.songs)
        }
        .overlay(alignment: .bottom) {
            StemProgressCard(stems: appModel.stems)
                .padding(.bottom, JGSpacing.xl + JGMetrics.statusBarHeight)
        }
        .sheet(item: Binding(get: { appModel.fileOps?.batchRenameRequest }, set: { appModel.fileOps?.batchRenameRequest = $0 })) {
            if let fileOps = appModel.fileOps {
                BatchRenameSheet(fileOps: fileOps, files: $0.files)
            }
        }
        .frame(minWidth: JGMetrics.windowMinWidth, minHeight: JGMetrics.windowMinHeight)
        .task {
            await appModel.start()
            await DeveloperHooks.run(appModel)
        }
        // Closing the window stops all playback — viewer, preview, Quick Preview (no background mode, D-63, D-78);
        // a viewer opened on its own quits the app.
        .onDisappear {
            if appModel.isViewerOnly {
                NSApp.terminate(nil)
                return
            }
            if appModel.mediaViewer != nil {
                appModel.closeViewer()
            }
            appModel.quickPreview?.close()
            appModel.playback.stop()
            appModel.windowPlayer.close()
        }
    }
}

/// Menu commands of the library; shortcuts come from Settings → Shortcuts.
struct LibraryCommands: Commands {
    let appModel: AppModel

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button {
                AboutPanel.show(store: appModel.settingsStore)
            } label: {
                Text("About \(AppIdentity.name)", comment: "App menu: the About panel; the argument is the app's name")
            }
        }
        CommandGroup(after: .newItem) {
            FileMenuItems(appModel: appModel)
            ActionMenuItems(appModel: appModel)
            FlagMenu(appModel: appModel)
        }
        CommandGroup(after: .toolbar) {
            ViewMenuItems(appModel: appModel)
        }
        CommandGroup(after: .pasteboard) {
            FindMenuItem(appModel: appModel)
        }
    }
}

/// File ▸ Add Folder…, New Album.
private struct FileMenuItems: View {
    let appModel: AppModel

    var body: some View {
        let shortcuts = appModel.shortcuts
        Button {
            Task { await appModel.library?.addFolders(FolderPicker.chooseFolders()) }
        } label: {
            Text("Add Folder…")
        }
        .keyboardShortcut(shortcuts.keyboardShortcut(for: .addFolder))
        .disabled(appModel.library == nil)
        Button {
            Task {
                guard let library = appModel.activeLibrary else { return }
                // With files selected in the grid, the new album holds them.
                let selected = appModel.viewer == nil ? library.actionTarget(sample: nil)?.assetIDs ?? [] : []
                let name = String(localized: "New Album", comment: "Default name of a new album")
                if let id = await library.createAlbum(name: name, with: selected) {
                    library.renamingAlbumID = id
                }
            }
        } label: {
            Text("New Album", comment: "Default name of a new album")
        }
        .keyboardShortcut(shortcuts.keyboardShortcut(for: .newAlbum))
        .disabled(appModel.library == nil)
    }
}

/// Edit ▸ Find (⌘F): the search field of the library's top bar; Find Duplicates… opens its window (W-78).
private struct FindMenuItem: View {
    let appModel: AppModel
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Divider()
        Button {
            appModel.closeViewer()
            appModel.activeLibrary?.requestSearchFocus()
        } label: {
            Text("Find", comment: "Menu: focuses the search field")
        }
        .keyboardShortcut(appModel.shortcuts.keyboardShortcut(for: .find))
        .disabled(appModel.library == nil)
        Button {
            openWindow(id: SceneID.duplicates)
        } label: {
            Text("Find Duplicates…", comment: "Edit menu: opens the window of copies of the same file")
        }
        .disabled(appModel.library == nil)
    }
}

/// View ▸ Show Names, Include Subfolders (the active pane's), Show Preview, Show Status Bar, Split View.
private struct ViewMenuItems: View {
    let appModel: AppModel

    var body: some View {
        if let main = appModel.library, let library = appModel.activeLibrary {
            let shortcuts = appModel.shortcuts
            Toggle(isOn: Binding(get: { library.state.showNames }, set: { library.setShowNames($0) })) {
                Text("Show Names", comment: "View menu: names under thumbnails")
            }
            .keyboardShortcut(shortcuts.keyboardShortcut(for: .showNames))
            Toggle(isOn: Binding(get: { library.state.includeSubfolders }, set: { library.setIncludeSubfolders($0) })) {
                Text("Include Subfolders")
            }
            .keyboardShortcut(shortcuts.keyboardShortcut(for: .includeSubfolders))
            Toggle(isOn: Binding(get: { main.state.previewVisible }, set: { main.setPreviewVisible($0) })) {
                Text("Show Preview", comment: "View menu: the preview pane on the right")
            }
            .keyboardShortcut(shortcuts.keyboardShortcut(for: .togglePreview))
            Toggle(isOn: Binding(
                get: { appModel.settingsStore.settings.showsStatusBar },
                set: { isOn in appModel.settingsStore.update { $0.showsStatusBar = isOn } }
            )) {
                Text("Show Status Bar", comment: "View menu: the counts under the files")
            }
            Divider()
            Picker(selection: Binding(get: { appModel.splitMode }, set: { appModel.setSplitMode($0) })) {
                Text("Off", comment: "View ▸ Split View: one pane").tag(LibraryViewState.SplitMode.off)
                Text("Side by Side", comment: "View ▸ Split View: two panes, left and right").tag(LibraryViewState.SplitMode.sideBySide)
                Text("Stacked", comment: "View ▸ Split View: two panes, top and bottom").tag(LibraryViewState.SplitMode.stacked)
            } label: {
                Text("Split View", comment: "View menu: two library panes side by side")
            }
            Button {
                appModel.toggleSplitView()
            } label: {
                Text("Toggle Split View", comment: "View menu: turns the split view on or off")
            }
            .keyboardShortcut(shortcuts.keyboardShortcut(for: .toggleSplitView))
        }
    }
}
