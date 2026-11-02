import AppKit
import JGModel

/// End-to-end check of PLAN Phase 7's "Done when" on test copies: in the photos-only filter, select everything,
/// Move to a folder, check that the asset ids followed the files, Undo, check they are back.
@MainActor
enum FileOpsCheck {
    static func run(appModel: AppModel, library: LibraryModel, destination: URL) async {
        guard let fileOps = appModel.fileOps else { return }
        if library.state.kinds != [.photo] {
            for kind in MediaKind.allCases where kind != .photo && library.state.kinds.contains(kind) {
                library.toggleKind(kind)
            }
        }
        try? await Task.sleep(for: .milliseconds(500))
        var selection = SelectionModel()
        selection.selectAll(library.order)
        library.selection = selection
        guard let target = library.actionTarget(sample: nil) else {
            log("nothing selected")
            return
        }
        let urls = await target.urls()
        log("photos selected: \(urls.count), kinds: \(target.kinds.map(\.rawValue).sorted())")
        fileOps.transfer(urls, to: destination, copying: false)
        await waitUntilIdle(fileOps)
        let moved = (try? FileManager.default.contentsOfDirectory(atPath: destination.path).count) ?? 0
        var kept = 0
        for (id, url) in zip(target.assetIDs, urls) {
            let path = destination.appendingPathComponent(url.lastPathComponent).path
            let found = await (try? library.store.location(of: path, isDirectory: false))??.assetID
            kept += found == id ? 1 : 0
        }
        log("after move: \(moved) files in destination, \(kept) of \(urls.count) asset ids kept, toast: \(fileOps.toast?.message ?? "-")")
        fileOps.undo()
        await waitUntilIdle(fileOps)
        let back = urls.filter { FileManager.default.fileExists(atPath: $0.path) }.count
        var restored = 0
        for (id, url) in zip(target.assetIDs, urls) {
            let found = await (try? library.store.location(of: url.path, isDirectory: false))??.assetID
            restored += found == id ? 1 : 0
        }
        log("after undo: \(back) of \(urls.count) files back, \(restored) ids in place, redo available: \(!fileOps.redoStack.isEmpty)")
    }

    private static func waitUntilIdle(_ fileOps: FileOperationsModel) async {
        try? await Task.sleep(for: .milliseconds(100))
        while fileOps.isRunning {
            try? await Task.sleep(for: .milliseconds(50))
        }
    }

    private static func log(_ line: String) {
        FileHandle.standardError.write(Data("file ops check: \(line)\n".utf8))
    }
}
