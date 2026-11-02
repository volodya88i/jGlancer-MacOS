import AppKit

/// `-JGFinderPreviewCheck <file>`: calls the Services entry point with the file on a private pasteboard, as Finder
/// would, then moves to the next file and logs what is shown (snapshot the panel with `-JGSnapshotPanel`).
@MainActor
enum FinderPreviewCheck {
    static func run(appModel: AppModel, delegate: AppDelegate?, file: URL) async {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("jGlancer.FinderPreviewCheck"))
        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])
        guard let delegate else {
            log("no services provider")
            return
        }
        delegate.quickPreview(pasteboard, userData: nil, error: nil)
        try? await Task.sleep(for: .milliseconds(1500))
        let shown = appModel.preview?.asset?.name ?? "-"
        let count = appModel.preview?.externalFiles.count ?? 0
        log("open: \(appModel.quickPreview?.isOpen == true), shown: \(shown), files: \(count)")
        appModel.preview?.moveExternal(by: 1)
        try? await Task.sleep(for: .milliseconds(800))
        log("after →: \(appModel.preview?.asset?.name ?? "-")")
    }

    private static func log(_ line: String) {
        FileHandle.standardError.write(Data("finder preview check: \(line)\n".utf8))
    }
}
