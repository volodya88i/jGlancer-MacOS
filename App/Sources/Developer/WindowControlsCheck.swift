import AppKit
import JGDesign

/// -JGWindowControlsCheck: logs where the close button's centre sits below the window's top edge, before and after a
/// resize; it should be half the top bar's height (D-114). Then the see-through photo viewer on and off.
@MainActor
enum WindowControlsCheck {
    static func run(_ appModel: AppModel, library: LibraryModel) async {
        try? await Task.sleep(for: .milliseconds(800))
        guard let window = DeveloperHooks.mainWindow else { return }
        log("at start: \(offset(in: window))")
        var frame = window.frame
        frame.size.width += 120
        window.setFrame(frame, display: true)
        try? await Task.sleep(for: .milliseconds(300))
        log("after a resize: \(offset(in: window))")
        guard let photo = library.refs.first(where: { $0.kind == .photo }) else { return }
        // A viewer in a window made smaller stays inside it (D-115).
        await appModel.openViewer(assetID: photo.id)
        try? await Task.sleep(for: .milliseconds(500))
        var smaller = window.frame
        smaller.size.width -= 300
        smaller.size.height -= 150
        window.setFrame(smaller, display: true)
        try? await Task.sleep(for: .milliseconds(400))
        log("viewer after shrinking: \(viewerFrame(in: window)) in a \(Int(window.contentLayoutRect.width)) × "
            + "\(Int(window.frame.height)) window")
        appModel.closeViewer()
        try? await Task.sleep(for: .milliseconds(300))
        // The see-through photo viewer (D-114): the window turns clear while a photo is open, and back after.
        appModel.settingsStore.update { $0.translucentPhotoViewer = true }
        await appModel.openViewer(assetID: photo.id)
        try? await Task.sleep(for: .milliseconds(500))
        log("photo open, see-through: window opaque \(window.isOpaque)")
        appModel.closeViewer()
        try? await Task.sleep(for: .milliseconds(500))
        log("photo closed: window opaque \(window.isOpaque)")
        appModel.settingsStore.update { $0.translucentPhotoViewer = false }
    }

    private static func offset(in window: NSWindow) -> String {
        guard let close = window.standardWindowButton(.closeButton) else { return "no button" }
        let rect = close.convert(close.bounds, to: nil)
        return String(format: "centre %.1f pt below the top (bar centre %.1f), x %.1f", window.frame.height - rect.midY,
                      JGMetrics.barHeight / 2, rect.minX)
    }

    private static func viewerFrame(in window: NSWindow) -> String {
        func find(_ view: NSView) -> NSView? {
            String(describing: type(of: view)) == "PhotoScrollView" ? view : view.subviews.lazy.compactMap(find).first
        }
        guard let view = window.contentView.flatMap(find) else { return "no viewer" }
        let rect = view.convert(view.bounds, to: nil)
        return "x \(Int(rect.minX)) y \(Int(rect.minY)) \(Int(rect.width)) × \(Int(rect.height))"
    }

    private static func log(_ line: String) {
        FileHandle.standardError.write(Data("window controls check: \(line)\n".utf8))
    }
}
