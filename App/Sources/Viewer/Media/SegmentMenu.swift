import AppKit
import JGDesign
import JGPlayback

/// The menu of a right click on the segment (D-74): Save As…, and Edit In ▸ the apps that open the exported file's
/// type (the default first), then Other….
@MainActor
enum SegmentMenu {
    static func make(for model: MediaViewerModel) -> NSMenu? {
        guard let request = model.segmentExport else { return nil }
        let menu = NSMenu()
        menu.addItem(ClosureMenuItem(title: String(localized: "Save As…", comment: "Segment menu: save the segment as a file")) {
            SegmentSaving.saveAs(SegmentRender(request: request))
        })
        let edit = NSMenuItem(
            title: String(localized: "Edit In", comment: "Segment menu: open the segment in another app"),
            action: nil,
            keyEquivalent: ""
        )
        edit.submenu = editMenu(for: request)
        menu.addItem(edit)
        return menu
    }

    private static func editMenu(for request: SegmentExportRequest) -> NSMenu {
        let menu = NSMenu()
        let ownID = Bundle.main.bundleIdentifier
        if let type = SegmentRender.contentType(for: request) {
            let defaultApp = NSWorkspace.shared.urlForApplication(toOpen: type)?.standardizedFileURL
            let apps = NSWorkspace.shared.urlsForApplications(toOpen: type)
                .map(\.standardizedFileURL)
                .filter { Bundle(url: $0)?.bundleIdentifier != ownID }
                .sorted { ($0 == defaultApp ? 0 : 1, $0.lastPathComponent) < ($1 == defaultApp ? 0 : 1, $1.lastPathComponent) }
            for app in apps {
                let title = OpenWithTitles.title(name: OpenWithStore.appName(app), isInstalled: true, isDefault: app == defaultApp)
                let item = ClosureMenuItem(title: title) {
                    SegmentSaving.edit(SegmentRender(request: request), in: app)
                }
                let icon = NSWorkspace.shared.icon(forFile: app.path)
                icon.size = NSSize(width: JGMetrics.iconSize, height: JGMetrics.iconSize)
                item.image = icon
                menu.addItem(item)
            }
            if !apps.isEmpty {
                menu.addItem(.separator())
            }
        }
        menu.addItem(ClosureMenuItem(title: String(localized: "Other…", comment: "Open With: choose any app")) {
            SegmentSaving.editInOtherApp(SegmentRender(request: request))
        })
        return menu
    }
}
