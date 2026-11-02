import AppKit
import JGDesign
import SwiftUI

/// "Open With" for a file the app cannot show (DECISIONS D-10): the other apps macOS offers for it.
/// The full Open With feature (primary apps, shortcuts) comes with the context menu in Phase 6.
struct OpenWithMenu: View {
    let url: URL

    var body: some View {
        Menu {
            ForEach(Self.applications(for: url), id: \.self) { app in
                Button {
                    NSWorkspace.shared.open([url], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
                } label: {
                    Text(verbatim: OpenWithStore.appName(app))
                }
            }
        } label: {
            Text("Open With", comment: "Menu of other apps that can open the file")
        }
        .menuStyle(.button)
        .buttonStyle(.jg(.secondary))
        .fixedSize()
    }

    /// Apps that can open `url`, without this one.
    static func applications(for url: URL) -> [URL] {
        NSWorkspace.shared.urlsForApplications(toOpen: url).filter {
            Bundle(url: $0)?.bundleIdentifier != Bundle.main.bundleIdentifier
        }
    }
}

/// Shows the file selected in a Finder window.
struct RevealInFinderButton: View {
    let url: URL

    var body: some View {
        Button {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } label: {
            Text("Reveal in Finder")
        }
        .buttonStyle(.jg(.secondary))
    }
}
