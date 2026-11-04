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
            // -JGQuickPreviewNarrow <png>: the panel squeezed; it stops where its controls row still fits (D-112).
            if let narrow = DeveloperHooks.defaults.string(forKey: "JGQuickPreviewNarrow") {
                for width in [230.0, 420] {
                    panel.setContentSize(NSSize(width: width, height: 520))
                    try? await Task.sleep(for: .milliseconds(400))
                    let url = URL(fileURLWithPath: narrow).deletingPathExtension().appendingPathExtension("\(Int(width)).png")
                    DeveloperHooks.snapshot(panel, to: url)
                    log("asked \(Int(width)) pt, got \(Int(panel.frame.width)) pt")
                }
            }
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
