import AppKit
import Foundation
import JGDesign
import SwiftUI

/// -JGDuplicatesCheck <png>: Find Duplicates on the library (logged and snapshotted), then Move to Trash with the
/// Trash replaced by a log line, so a check never fills the user's Trash.
@MainActor
enum DuplicatesCheck {
    static func run(_ appModel: AppModel, library: LibraryModel, snapshot: URL) async {
        try? await Task.sleep(for: .seconds(2))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: JGMetrics.duplicatesWidth, height: JGMetrics.duplicatesHeight),
            styleMask: [.titled], backing: .buffered, defer: false
        )
        window.contentView = NSHostingView(rootView: DuplicatesView(appModel: appModel).appSettings(appModel.settingsStore))
        window.orderFront(nil)
        try? await Task.sleep(for: .milliseconds(1500))
        DeveloperHooks.snapshot(window, to: snapshot)
        window.orderOut(nil)
        let model = DuplicatesModel(store: library.store, thumbnails: library.thumbnails)
        model.onTrash = { urls in log("would trash: \(urls.map { $0.path.replacingOccurrences(of: NSTemporaryDirectory(), with: "") })") }
        await model.scan()
        for group in model.plan.groups {
            log("group: " + group.copies.map { "\($0.name)\(model.plan.isTicked($0.id) ? " ✓" : "")" }.joined(separator: ", "))
        }
        log("pending \(model.pending); keeping the last unticked copy refused: \(!model.toggle(model.plan.groups.first?.id ?? 0))")
        await model.moveTickedToTrash()
        log("message: \(model.message ?? "-"); groups left \(model.plan.groups.count)")
    }

    private static func log(_ line: String) {
        FileHandle.standardError.write(Data("duplicates check: \(line)\n".utf8))
    }
}
