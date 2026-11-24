import Foundation
import JGModel

/// -JGSizeMapCheck <png>: the size map under the files with three files selected, then moved right and back twice
/// (each move makes a new canvas that gets the tree and the selection at once), then into a subfolder and back; logs
/// each place and a snapshot at the end (D-127).
@MainActor
enum SizeMapCheck {
    static func run(_ appModel: AppModel, library: LibraryModel, snapshot: URL) async {
        library.setModuleVisible(.sizeMap, true)
        if library.state.slot(of: .sizeMap) != .bottom {
            library.moveModule(.sizeMap)
        }
        var selection = SelectionModel()
        selection.restore(library.refs.prefix(3).map(\.id), focus: library.refs.first?.id)
        library.selection = selection
        try? await Task.sleep(for: .milliseconds(1200))
        log("tree of \(appModel.sizeMap.tree.nodes.count) nodes, \(library.selection.selected.count) selected")
        for _ in 1 ... 4 {
            library.moveModule(.sizeMap)
            log("size map \(place(library)), preview \(library.state.slot(of: .preview)?.rawValue ?? "hidden")")
            try? await Task.sleep(for: .milliseconds(300))
        }
        if let root = library.state.folderID, let child = library.folderNode(id: root)?.children?.first?.id {
            library.select(folderID: child)
            try? await Task.sleep(for: .milliseconds(600))
            log("subfolder: tree of \(appModel.sizeMap.tree.nodes.count) nodes")
            library.select(folderID: root)
            library.moveModule(.sizeMap)
            try? await Task.sleep(for: .milliseconds(800))
            log("back: tree of \(appModel.sizeMap.tree.nodes.count) nodes, size map \(place(library))")
        }
        if let window = DeveloperHooks.mainWindow {
            DeveloperHooks.snapshot(window, to: snapshot)
        }
    }

    private static func place(_ library: LibraryModel) -> String {
        library.state.slot(of: .sizeMap)?.rawValue ?? "hidden"
    }

    private static func log(_ line: String) {
        FileHandle.standardError.write(Data("size map check: \(line)\n".utf8))
    }
}
