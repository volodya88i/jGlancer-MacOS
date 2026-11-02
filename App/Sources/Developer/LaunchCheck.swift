import AppKit

/// `-JGLaunchLog <file>` (pass it through `open -a jGlancer.app <media> --args …` to launch as Finder does): after
/// 2 s writes whether the viewer alone is open and whether the library loaded, then closes the main window as its
/// close button would. A viewer opened on its own should then quit the app.
@MainActor
enum LaunchCheck {
    static func run(_ appModel: AppModel, log url: URL) async {
        try? await Task.sleep(for: .seconds(2))
        let line = "viewer only: \(appModel.isViewerOnly), viewer: \(appModel.viewer != nil), library loaded: \(appModel.library != nil)\n"
        try? Data(line.utf8).write(to: url)
        DeveloperHooks.mainWindow?.performClose(nil)
    }
}
