import AppKit
import JGDesign
import SwiftUI

/// The library window (docs/DESIGN.md §8): sidebar · one pane, or two in a split view (D-89) · preview pane.
struct LibraryView: View {
    /// The main pane: the sidebar's trees and albums, the preview pane, the split's mode and divider.
    let model: LibraryModel
    let preview: PreviewModel?
    /// Opens dropped files and folders (folders join the library, photos open in the viewer).
    let onOpen: ([URL]) -> Void
    /// The window's mini player (D-88) and its folder link.
    var miniPlayer: WindowPlayerModel?
    var onShowMiniPlayerSong: (Int64) -> Void = { _ in }
    /// The split view's second pane, whether it is the active one, and the divider's setter (D-89).
    var secondPane: LibraryModel?
    var isSecondPaneActive = false
    var onSplitFraction: (Double) -> Void = { _ in }

    var body: some View {
        // The mini player spans the whole window under the sidebar, the panes and the preview, as on Windows; the side
        // columns give way to the window's width, not the content's (D-111).
        GeometryReader { window in
            VStack(spacing: 0) {
                columns(width: window.size.width)
                playerBar
            }
            .frame(width: window.size.width, height: window.size.height)
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(JGColor.bgBase)
    }

    private func columns(width: CGFloat) -> some View {
        let preview = previewWidth(in: width)
        let sidebar = sidebarWidth(in: width, preview: preview)
        return HStack(spacing: 0) {
            SidebarView(model: model, target: isSecondPaneActive ? secondPane : model)
                .frame(width: sidebar)
                .overlay(alignment: .trailing) {
                    PaneResizeHandle(width: sidebar, growsTowardLeading: false, set: model.setSidebarWidth)
                }
            JGHairline(.vertical)
            VStack(spacing: 0) {
                if let secondPane, model.state.splitMode != .off {
                    SplitPanes(
                        isStacked: model.state.splitMode == .stacked, fraction: model.state.splitFraction, set: onSplitFraction
                    ) {
                        LibraryPaneView(model: model, onOpen: onOpen, showsActiveEdge: !isSecondPaneActive)
                    } second: {
                        LibraryPaneView(model: secondPane, onOpen: onOpen, showsActiveEdge: isSecondPaneActive)
                    }
                } else {
                    LibraryPaneView(model: model, onOpen: onOpen)
                }
            }
            if let previewModel = self.preview, showsPreview {
                JGHairline(.vertical)
                PreviewPane(preview: previewModel, library: model, pane: isSecondPaneActive ? secondPane : model)
                    .frame(width: preview)
            }
        }
    }

    private var showsPreview: Bool {
        preview != nil && model.state.previewVisible && !model.roots.isEmpty
    }

    /// The preview's chosen width, narrower when the window leaves the panes less than their minimum (D-111).
    private func previewWidth(in width: CGFloat) -> CGFloat {
        guard showsPreview else { return 0 }
        let room = width - JGMetrics.libraryPaneMinWidth - JGMetrics.sidebarMinWidth
        return max(JGMetrics.previewPaneMinWidth, min(model.state.previewWidth, room))
    }

    /// The sidebar's chosen width, narrower as for the preview.
    private func sidebarWidth(in width: CGFloat, preview: CGFloat) -> CGFloat {
        max(JGMetrics.sidebarMinWidth, min(model.state.sidebarWidth, width - JGMetrics.libraryPaneMinWidth - preview))
    }

    @ViewBuilder
    private var playerBar: some View {
        if let player = miniPlayer, player.isOpen {
            JGHairline()
            WindowPlayerBar(player: player, onShowSong: onShowMiniPlayerSong)
        }
    }
}

/// Two panes side by side or stacked, with a draggable hairline between them; `fraction` is the first one's share.
private struct SplitPanes<First: View, Second: View>: View {
    let isStacked: Bool
    let fraction: Double
    let set: (Double) -> Void
    @ViewBuilder var first: First
    @ViewBuilder var second: Second
    @State private var startLength: Double?

    var body: some View {
        GeometryReader { geometry in
            let total = Double(isStacked ? geometry.size.height : geometry.size.width)
            let length = (total * fraction).rounded()
            let layout = isStacked ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
            layout {
                first
                    .frame(width: isStacked ? nil : length, height: isStacked ? length : nil)
                JGHairline(isStacked ? .horizontal : .vertical)
                    .overlay { handle(length: length, total: total) }
                second
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }

    private func handle(length: Double, total: Double) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: isStacked ? nil : JGMetrics.resizeHandleWidth, height: isStacked ? JGMetrics.resizeHandleWidth : nil)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    (isStacked ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = startLength ?? length
                        startLength = start
                        guard total > 0 else { return }
                        set((start + (isStacked ? drag.translation.height : drag.translation.width)) / total)
                    }
                    .onEnded { _ in startLength = nil }
            )
            .accessibilityHidden(true)
    }
}

/// First run: one headline, one line, one button (docs/DESIGN.md §8).
struct EmptyLibraryView: View {
    let model: LibraryModel

    var body: some View {
        JGEmptyState(
            label: Text("Library", comment: "Section label of the library screen; shown in capitals"),
            title: AttributedString(localized: "Add a **folder**.", comment: "First-run headline; ** marks the accent word"),
            message: Text("Files stay where they are.", comment: "First-run line under the headline")
        ) {
            Button {
                Task { await model.addFolders(FolderPicker.chooseFolders()) }
            } label: {
                Text("Add Folder…", comment: "Button and menu item that adds a folder to the library")
            }
            .buttonStyle(.jg(.primary))
            .keyboardShortcut(.defaultAction)
            Text("or drop a folder here", comment: "Hint next to the Add Folder button")
                .jgTextStyle(.body)
                .foregroundStyle(JGColor.textTertiary)
        }
        .padding(JGSpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}
