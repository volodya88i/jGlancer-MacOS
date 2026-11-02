import JGModel

/// Split view (D-89, W-66): two panes, side by side or stacked. The second follows the main pane's roots, trees and
/// albums and has its own view state; the pane last clicked is active, and the sidebar, actions, menus, the preview
/// and Quick Preview apply to it.
extension AppModel {
    /// The pane actions and menus apply to.
    var activeLibrary: LibraryModel? {
        isSecondPaneActive ? secondPane ?? library : library
    }

    var splitMode: LibraryViewState.SplitMode {
        library?.state.splitMode ?? .off
    }

    func setSplitMode(_ mode: LibraryViewState.SplitMode) {
        guard let library else { return }
        library.updateState {
            $0.splitMode = mode
            if mode != .off {
                $0.lastSplit = mode.rawValue
            }
        }
        if mode == .off {
            if let secondPane {
                secondPane.stopFollowing(library)
                self.secondPane = nil
            }
            activate(library)
        } else if secondPane == nil {
            let pane = LibraryModel(
                following: library,
                stateStore: ViewStateStore(isPersistent: AppPaths.dataOverride == nil, key: ViewStateStore.secondPaneKey)
            )
            connectPane(pane)
            pane.startFollowing(library)
            secondPane = pane
        }
    }

    /// ⌃⌘S: off, or back to the last arrangement (side by side the first time).
    func toggleSplitView() {
        setSplitMode(splitMode == .off ? lastSplitMode : .off)
    }

    private var lastSplitMode: LibraryViewState.SplitMode {
        let stored = library.flatMap { LibraryViewState.SplitMode(rawValue: $0.state.lastSplit) } ?? .sideBySide
        return stored == .off ? .sideBySide : stored
    }

    func setSplitFraction(_ fraction: Double) {
        library?.updateState { $0.splitFraction = min(max(fraction, 0.2), 0.8) }
    }

    /// The pane clicked or used last becomes active; the preview follows its selection.
    func activate(_ pane: LibraryModel) {
        let second = pane === secondPane
        guard second != isSecondPaneActive else { return }
        isSecondPaneActive = second
        preview?.selectionChanged(pane.selection)
    }

    /// The saved split comes back with the library.
    func restoreSplit() {
        if splitMode != .off {
            let mode = splitMode
            library?.updateState { $0.splitMode = .off }
            setSplitMode(mode)
        }
    }
}
