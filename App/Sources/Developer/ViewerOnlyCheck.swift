import AppKit

/// `-JGViewerOnly <file> -JGViewerOnlyLibrary YES`: logs that no library is loaded behind the viewer, presses
/// "‹ Library" and logs that the library loaded and the viewer closed.
@MainActor
enum ViewerOnlyCheck {
    static func run(_ appModel: AppModel) async {
        for _ in 0 ..< 30 where appModel.viewer == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        log("viewer: \(appModel.viewer != nil), library loaded: \(appModel.library != nil), viewer only: \(appModel.isViewerOnly)")
        appModel.closeViewer()
        for _ in 0 ..< 50 where appModel.viewer != nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        let state = "viewer: \(appModel.viewer != nil), library loaded: \(appModel.library != nil)"
        log("after Library: \(state), viewer only: \(appModel.isViewerOnly)")
    }

    private static func log(_ line: String) {
        FileHandle.standardError.write(Data("viewer only check: \(line)\n".utf8))
    }
}
