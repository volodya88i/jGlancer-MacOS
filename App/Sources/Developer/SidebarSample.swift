import AppKit
import JGModel
import SwiftUI

/// -JGSidebarSample YES (with `-JGRootIcon <emoji | sf:symbol | /path/to/picture | photo>`): two albums of the first photos
/// (none moved; albums are only rows in the test library) and the first library folder's icon, for snapshots of the
/// sidebar and its strip (D-128, D-129).
@MainActor
enum SidebarSample {
    static func run(_ library: LibraryModel) async {
        if library.albums.isEmpty {
            let photos = await (try? library.store.assetRefs(for: AssetQuery(kinds: [.photo]))) ?? []
            let ids = photos.map(\.id)
            _ = await library.createAlbum(name: "Trip", with: Array(ids.prefix(3)))
            _ = await library.createAlbum(name: "Portraits", with: Array(ids.dropFirst(3).prefix(2)))
        }
        if let value = UserDefaults.standard.string(forKey: "JGRootIcon"), let root = library.roots.first {
            if value == "photo" {
                // Use as Folder Icon on the first photo.
                let photos = await (try? library.store.assetRefs(for: AssetQuery(kinds: [.photo]))) ?? []
                if let first = photos.first {
                    await library.setFolderIcon(fromAsset: first.id)
                }
            } else if value.hasPrefix("/") {
                library.setRootIcon(fromFile: URL(fileURLWithPath: value), for: root.id)
            } else if value.hasPrefix("sf:") {
                library.setRootIcon(.symbol(String(value.dropFirst(3))), for: root.id)
            } else {
                library.setRootIcon(.emoji(value), for: root.id)
            }
        }
        try? await Task.sleep(for: .milliseconds(800))
        FileHandle.standardError
            .write(Data("sidebar sample: albums \(library.albums.map(\.name)), icons \(library.rootIcons.count)\n".utf8))
        // `-JGIconPickerSnapshot <png>`: Folder Icon… for the first library folder, drawn offscreen.
        if let output = UserDefaults.standard.string(forKey: "JGIconPickerSnapshot"), let root = library.roots.first {
            let view = NSHostingView(rootView: FolderIconPicker(model: library, root: root))
            view.appearance = DeveloperHooks.mainWindow?.effectiveAppearance
            view.frame = NSRect(origin: .zero, size: view.fittingSize)
            view.layoutSubtreeIfNeeded()
            if let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) {
                view.cacheDisplay(in: view.bounds, to: rep)
                try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: output))
            }
        }
    }

    /// -JGSidebarHitCheck YES: what takes a click beside the folded strip, where the unfolded sidebar would be (the
    /// files should), and on the strip itself (the sidebar should); logged.
    static func hitCheck(_ library: LibraryModel) async {
        library.setSidebarCollapsed(true)
        try? await Task.sleep(for: .seconds(1))
        guard let window = DeveloperHooks.mainWindow, let content = window.contentView else { return }
        let buttons = [NSWindow.ButtonType.closeButton, .zoomButton].compactMap { window.standardWindowButton($0)?.frame }
        let spans = buttons.map { "\($0.minX)…\($0.maxX)" }
        let room = "close \(spans.first ?? "-"), zoom \(spans.last ?? "-")"
        FileHandle.standardError.write(Data("sidebar hit check: buttons \(room), room \(WindowControlsRoom.shared.width)\n".utf8))
        let height = content.bounds.height
        for x in [CGFloat(20), 120, 200] {
            let point = NSPoint(x: x, y: height / 2)
            let hit = content.hitTest(point)
            var chain: [String] = []
            var view = hit
            while let current = view, chain.count < 12 {
                chain.append(String(describing: type(of: current)))
                view = current.superview
            }
            let isFiles = chain.contains { $0.contains("CollectionView") || $0.contains("ListController") || $0.contains("OutlineView") }
            let line = "sidebar hit check: x \(Int(x)) → \(isFiles ? "files" : "not files") [\(chain.prefix(3).joined(separator: " < "))]"
            FileHandle.standardError.write(Data((line + "\n").utf8))
        }
    }

    /// -JGSidebarMorph <png> (with -JGSnapshotSize): the strip opening, a frame early in the spring and one at its end.
    static func morph(_ appModel: AppModel, _ library: LibraryModel, size: String, to url: URL) async {
        guard let window = OffscreenSnapshot.window(appModel, size: size) else { return }
        try? await Task.sleep(for: .seconds(1.5))
        library.sidebarPeek.open()
        try? await Task.sleep(for: .milliseconds(90))
        DeveloperHooks.snapshot(window, to: url.deletingPathExtension().appendingPathExtension("early.png"))
        try? await Task.sleep(for: .milliseconds(900))
        DeveloperHooks.snapshot(window, to: url)
        window.orderOut(nil)
    }
}
