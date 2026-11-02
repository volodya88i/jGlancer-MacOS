import AppKit
import Foundation
import JGModel

/// -JGSplitCheck <png>: the split view side by side (the second pane in a subfolder, active), then stacked, then off;
/// a snapshot of each arrangement (D-89).
@MainActor
enum SplitCheck {
    static func run(_ appModel: AppModel, library: LibraryModel, snapshot: URL) async {
        try? await Task.sleep(for: .milliseconds(600))
        guard let window = DeveloperHooks.mainWindow else { return }
        appModel.setSplitMode(.sideBySide)
        try? await Task.sleep(for: .milliseconds(400))
        guard let pane = appModel.secondPane else {
            log("no second pane")
            return
        }
        let subfolder = library.roots.first.flatMap { library.trees[$0.id]?.children?.first?.folder.id }
        if let subfolder {
            pane.select(folderID: subfolder)
        }
        appModel.activate(pane)
        try? await Task.sleep(for: .milliseconds(1200))
        log("main: \(library.state.folderID ?? -1) \(library.refs.count) files; second: \(pane.state.folderID ?? -1) "
            + "\(pane.refs.count) files; active is second: \(appModel.activeLibrary === pane)")
        DeveloperHooks.snapshot(window, to: snapshot)
        appModel.setSplitFraction(0.3)
        appModel.setSplitMode(.stacked)
        try? await Task.sleep(for: .milliseconds(1000))
        DeveloperHooks.snapshot(window, to: snapshot.deletingPathExtension().appendingPathExtension("stacked.png"))
        appModel.toggleSplitView()
        try? await Task.sleep(for: .milliseconds(400))
        log("after toggling: \(appModel.splitMode), second pane: \(appModel.secondPane != nil), "
            + "active is main: \(appModel.activeLibrary === library)")
        appModel.toggleSplitView()
        log("toggled back: \(appModel.splitMode), fraction \(library.state.splitFraction)")
        appModel.setSplitMode(.off)
    }

    private static func log(_ line: String) {
        FileHandle.standardError.write(Data("split check: \(line)\n".utf8))
    }
}
