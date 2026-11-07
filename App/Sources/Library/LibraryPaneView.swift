import JGDesign
import JGSettings
import SwiftUI
import UniformTypeIdentifiers

/// One pane of the library window: top bar, grid, status bubble. A split view has two (D-89); the active one shows an
/// accent edge on top, and a click anywhere in a pane makes it active.
struct LibraryPaneView: View {
    let model: LibraryModel
    /// Opens dropped files and folders (folders join the library, photos open in the viewer).
    let onOpen: ([URL]) -> Void
    var showsActiveEdge = false
    @State private var isDropTargeted = false
    @Environment(\.appSettings) private var settings

    var body: some View {
        // The files run the pane's whole height and scroll under the top bar and the status bar, which are frosted
        // glass, as in Finder (D-114).
        ZStack {
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .overlay(alignment: .bottom) { AddingFoldersCard(model: model).padding(.bottom, bottomInset) }
                // Files and folders from Finder: folders join the library, files open. Tiles dragged inside the
                // app are not taken here; sidebar folders take them. A sidebar folder row shows its folder here.
                .onDrop(of: [.fileURL, .utf8PlainText], delegate: OpenDropDelegate(
                    isTargeted: $isDropTargeted, onOpen: onOpen, onFolder: showFolder
                ))
                .overlay {
                    if isDropTargeted {
                        Rectangle()
                            .strokeBorder(JGColor.accent, lineWidth: JGMetrics.selectionEdgeWidth)
                            .padding(.top, topInset)
                            .padding(.bottom, bottomInset)
                            .allowsHitTesting(false)
                    }
                }
            bars
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

    /// The top bar and the status bar over the files; the space between them lets clicks through.
    private var bars: some View {
        VStack(spacing: 0) {
            VStack(spacing: 0) {
                // The click that makes the pane active lies under the bar's controls, not over them: a gesture over
                // the whole bar took their clicks for the window's own view, and a drag on the size ruler moved the
                // window (D-112).
                TopBarView(model: model)
                    .frame(height: JGMetrics.barHeight)
                    .background { Color.clear.contentShape(Rectangle()).gesture(activation).titleBarDoubleClick() }
                JGHairline()
            }
            .jgBarBackground(JGColor.bgBase)
            Spacer(minLength: 0)
            // View → Show Status Bar (D-110): a bubble floating over the files, centred (D-116).
            if settings.showsStatusBar {
                StatusBarView(model: model)
                    .simultaneousGesture(activation)
                    .padding(.bottom, JGSpacing.xs)
            }
        }
    }

    /// The room the bars take at the top and the bottom of the files.
    private var topInset: CGFloat {
        JGMetrics.barHeight + JGMetrics.outlineWidth
    }

    /// The last row can scroll clear of the status bubble.
    private var bottomInset: CGFloat {
        settings.showsStatusBar ? JGMetrics.statusBubbleHeight + 2 * JGSpacing.xs : 0
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
                .padding(.top, topInset)
                .padding(.bottom, bottomInset)
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
            .padding(.top, topInset)
            .padding(.bottom, bottomInset)
        } else if model.state.viewMode == .list {
            // Finder-style list (D-125).
            LibraryListView(model: model, insets: NSEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0))
        } else {
            LibraryGridView(model: model, insets: NSEdgeInsets(top: topInset, left: 0, bottom: bottomInset, right: 0))
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
