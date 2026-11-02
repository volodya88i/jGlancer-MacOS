import JGDesign
import SwiftUI
import UniformTypeIdentifiers

/// One pane of the library window: top bar, grid, status bar. A split view has two (D-89); the active one shows an
/// accent edge on top, and a click anywhere in a pane makes it active.
struct LibraryPaneView: View {
    let model: LibraryModel
    /// Opens dropped files and folders (folders join the library, photos open in the viewer).
    let onOpen: ([URL]) -> Void
    var showsActiveEdge = false
    @State private var isDropTargeted = false

    var body: some View {
        VStack(spacing: 0) {
            TopBarView(model: model)
                .frame(height: JGMetrics.barHeight)
                .simultaneousGesture(activation)
            JGHairline()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) { AddingFoldersCard(model: model) }
                // Files and folders from Finder: folders join the library, files open. Tiles dragged inside the
                // app are not taken here; sidebar folders take them. A sidebar folder row shows its folder here.
                .onDrop(of: [.fileURL, .utf8PlainText], delegate: OpenDropDelegate(
                    isTargeted: $isDropTargeted, onOpen: onOpen, onFolder: showFolder
                ))
                .overlay {
                    if isDropTargeted {
                        Rectangle()
                            .strokeBorder(JGColor.accent, lineWidth: JGMetrics.selectionEdgeWidth)
                            .allowsHitTesting(false)
                    }
                }
            JGHairline()
            StatusBarView(model: model)
                .frame(height: JGMetrics.statusBarHeight)
                .simultaneousGesture(activation)
        }
        .overlay(alignment: .top) {
            if showsActiveEdge {
                Rectangle()
                    .fill(JGColor.accent)
                    .frame(height: JGMetrics.selectionEdgeWidth)
                    .allowsHitTesting(false)
            }
        }
    }

    /// A click on the bars makes the pane active; the grid reports its own clicks (AppKit, `onInteraction`).
    private var activation: some Gesture {
        TapGesture().onEnded { model.onInteraction?() }
    }

    private func showFolder(_ id: Int64) {
        model.onInteraction?()
        model.select(folderID: id)
    }

    @ViewBuilder
    private var content: some View {
        if model.roots.isEmpty {
            EmptyLibraryView(model: model)
        } else if model.isLoaded, model.refs.isEmpty {
            JGEmptyState(
                title: AttributedString(localized: "Nothing **here**.", comment: "Empty folder headline; ** marks the accent word"),
                message: Text("No files of the selected kinds.", comment: "Empty folder explanation"),
                isLarge: false
            ) {
                EmptyView()
            }
            .padding(JGSpacing.xxl)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        } else {
            LibraryGridView(model: model)
        }
    }
}

/// A sidebar folder row dragged onto a pane (D-89): the folder's id as text with a prefix of its own, so neither
/// Finder nor the sidebar's file drops take it for a file.
@MainActor
enum PaneFolderDrag {
    private static let prefix = "jglancer-folder:"

    static func provider(for folderID: Int64) -> NSItemProvider {
        NSItemProvider(object: "\(prefix)\(folderID)" as NSString)
    }

    static func folderID(from provider: NSItemProvider) async -> Int64? {
        let text: String? = await withCheckedContinuation { continuation in
            _ = provider.loadObject(ofClass: NSString.self) { object, _ in
                continuation.resume(returning: (object as? NSString).map(String.init))
            }
        }
        guard let text, text.hasPrefix(prefix) else { return nil }
        return Int64(text.dropFirst(prefix.count))
    }
}

/// Drops from Finder onto a pane, and sidebar folder rows; drags of the app's own tiles are refused.
private struct OpenDropDelegate: DropDelegate {
    @Binding var isTargeted: Bool
    let onOpen: ([URL]) -> Void
    let onFolder: (Int64) -> Void

    func validateDrop(info: DropInfo) -> Bool {
        !InternalDrag.isActive && info.hasItemsConforming(to: [.fileURL, .utf8PlainText])
    }

    func dropEntered(info _: DropInfo) {
        isTargeted = !InternalDrag.isActive
    }

    func dropExited(info _: DropInfo) {
        isTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        isTargeted = false
        guard !InternalDrag.isActive else { return false }
        if !info.hasItemsConforming(to: [.fileURL]), let provider = info.itemProviders(for: [.utf8PlainText]).first {
            Task {
                if let id = await PaneFolderDrag.folderID(from: provider) {
                    onFolder(id)
                }
            }
            return true
        }
        let providers = info.itemProviders(for: [.fileURL])
        Task {
            await onOpen(FolderPicker.urls(from: providers))
        }
        return true
    }
}
