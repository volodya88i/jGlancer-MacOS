import AppKit

/// Receives files and folders opened from Finder, the Dock or other apps (docs/FEATURES.md §13).
/// LaunchServices keeps one instance and forwards later opens to it.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let appModel = AppModel()

    /// True once launching is over; files that arrive before that launched the app.
    private var didFinishLaunching = false

    func application(_: NSApplication, open urls: [URL]) {
        if !didFinishLaunching {
            appModel.launchedWithFiles = true
        }
        Task { await appModel.open(urls) }
    }

    /// A viewer opened on its own quits with its window; the whole app stays (as Mac apps do).
    func applicationShouldTerminateAfterLastWindowClosed(_: NSApplication) -> Bool {
        appModel.isViewerOnly
    }

    /// Launched by opening files (Finder, Open With): the viewer alone, without the library (`AppModel.isViewerOnly`).
    func applicationWillFinishLaunching(_: Notification) {
        let event = NSAppleEventManager.shared().currentAppleEvent
        if event?.eventClass == AEEventClass(kCoreEventClass), event?.eventID == AEEventID(kAEOpenDocuments) {
            appModel.launchedWithFiles = true
        }
        // Developer hook: a launch by the Finder service (`-JGServiceLaunch <file>`, see ServiceLaunchCheck).
        if UserDefaults.standard.string(forKey: "JGServiceLaunch") != nil {
            appModel.launchedWithFiles = true
        }
        // Developer hook: the same launch, for tests (`-JGViewerOnly <file>`).
        if let path = UserDefaults.standard.string(forKey: "JGViewerOnly") {
            appModel.launchedWithFiles = true
            Task { await appModel.open([URL(fileURLWithPath: path)]) }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // False when LaunchServices started the app to open (or print) files.
        if notification.userInfo?[NSApplication.launchIsDefaultUserInfoKey] as? Bool == false {
            appModel.launchedWithFiles = true
        }
        didFinishLaunching = true
        appModel.launchDecided()
        appModel.mediaKeys.start()
        NSApp.servicesProvider = self
        // Lets macOS pick up the Services entry of a new or moved app without a new login.
        NSUpdateDynamicServices()
    }

    /// Finder ▸ Services ▸ "Quick Preview": the selected files in the app's Quick Preview (Info.plist `NSServices`).
    @objc func quickPreview(_ pasteboard: NSPasteboard, userData _: String?, error _: AutoreleasingUnsafeMutablePointer<NSString>?) {
        let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
        Task { await appModel.quickPreviewFromFinder(urls) }
    }
}
