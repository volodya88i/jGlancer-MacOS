import AppKit
import Foundation

/// -JGQuickPreviewOpenCheck YES (with -JGSelect 1): Quick Preview on the selection, its level and whether it hides
/// when the app is inactive, then Open in Viewer; logs the viewer's file.
@MainActor
enum QuickPreviewOpenCheck {
    static func run(_ appModel: AppModel) async {
        try? await Task.sleep(for: .milliseconds(800))
        guard let quickPreview = appModel.quickPreview else { return }
        let name = appModel.preview?.asset?.name ?? "-"
        quickPreview.open(over: DeveloperHooks.mainWindow)
        try? await Task.sleep(for: .milliseconds(500))
        if let panel = NSApp.windows.first(where: { $0 is QuickPreviewPanel }) {
            log("open \(quickPreview.isOpen), floating \(panel.level == .floating), hides when inactive \(panel.hidesOnDeactivate)")
        }
        appModel.openFromQuickPreview()
        try? await Task.sleep(for: .milliseconds(1000))
        log("previewed \(name); viewer shows \(appModel.photoViewer?.currentPhoto?.name ?? appModel.mediaViewer?.current?.name ?? "-"); "
            + "quick preview open \(quickPreview.isOpen)")
        appModel.closeViewer()
    }

    private static func log(_ line: String) {
        FileHandle.standardError.write(Data("quick preview open check: \(line)\n".utf8))
    }
}
