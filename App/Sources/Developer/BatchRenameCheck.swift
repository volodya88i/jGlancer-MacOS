import AppKit
import JGActions
import SwiftUI

/// `-JGBatchRenameCheck <snapshot.png>` with `-JGSelect N`: Rename… on the selection (snapshot of the sheet), then
/// "Trip {n}", checks that the library rows (same asset ids) carry the new names, undoes, checks again. Test copies only.
@MainActor
enum BatchRenameCheck {
    static func run(appModel: AppModel, library: LibraryModel, snapshot url: URL) async {
        guard let target = library.actionTarget(sample: nil), let fileOps = appModel.fileOps else { return }
        await appModel.actions.requestBatchRename(target)
        guard let files = fileOps.batchRenameRequest?.files else {
            log("no request")
            return
        }
        fileOps.batchRenameRequest = nil
        let window = NSWindow(contentViewController: NSHostingController(rootView: BatchRenameSheet(fileOps: fileOps, files: files)))
        window.orderFront(nil)
        try? await Task.sleep(for: .milliseconds(800))
        DeveloperHooks.snapshot(window, to: url)
        window.orderOut(nil)
        let ids = target.assetIDs
        await log("before: \(names(library, ids))")
        let names = BatchRenamePattern(template: "Trip {n}").names(for: files)
        fileOps.renameAll(zip(files, names).map { ($0.url, $1) })
        try? await Task.sleep(for: .seconds(1))
        await log("after: \(self.names(library, ids)), toast: \(fileOps.toast?.message ?? "-")")
        fileOps.undo()
        try? await Task.sleep(for: .seconds(1))
        await log("after undo: \(self.names(library, ids))")
    }

    private static func names(_ library: LibraryModel, _ ids: [Int64]) async -> [String] {
        await ((try? library.store.assets(ids: ids)) ?? []).map(\.name)
    }

    private static func log(_ line: String) {
        FileHandle.standardError.write(Data("batch rename check: \(line)\n".utf8))
    }
}
