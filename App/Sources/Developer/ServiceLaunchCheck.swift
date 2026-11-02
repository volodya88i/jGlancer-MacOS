import AppKit

/// `-JGServiceLaunch <file>`: as if Finder ▸ Services ▸ Quick Preview launched the app: calls the service with the file,
/// logs whether the panel is open and the main window hidden, then closes the panel (the app should quit).
@MainActor
enum ServiceLaunchCheck {
    static func run(_ appModel: AppModel, file: URL) async {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("jGlancer.ServiceLaunchCheck"))
        pasteboard.clearContents()
        pasteboard.writeObjects([file as NSURL])
        (NSApp.servicesProvider as? AppDelegate)?.quickPreview(pasteboard, userData: nil, error: nil)
        try? await Task.sleep(for: .seconds(3))
        let windowShown = NSApp.windows.contains { !($0 is NSPanel) && $0.isVisible }
        let line = "panel open: \(appModel.quickPreview?.isOpen == true), shown: \(appModel.preview?.asset?.name ?? "-"), "
            + "main window visible: \(windowShown)\n"
        FileHandle.standardError.write(Data(("service launch check: " + line).utf8))
        appModel.quickPreview?.close()
    }
}
