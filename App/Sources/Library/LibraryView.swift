import AppKit
import JGDesign
import JGModel
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
    /// The size map module's data (D-127).
    var sizeMap: SizeMapModel?
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var reduceMotionOverride
    /// The sidebar panel (D-128): at its full width (docked, or out over the files) or the strip; and whether the files
    /// leave it its full width. Unfolding, the panel opens first and the files make room when it is out.
    @State private var isPanelOpen = true
    @State private var reservesSidebar = true

    var body: some View {
        // The mini player spans the whole window under the sidebar, the panes and the preview, as on Windows; the side
        // columns give way to the window's width, not the content's (D-111).
        GeometryReader { window in
            VStack(spacing: 0) {
                columns(width: window.size.width)
                playerBar
            }
            .frame(width: window.size.width, height: window.size.height)
            .onChange(of: window.size.width < JGMetrics.sidebarAutoCollapseWidth, initial: true) { _, isNarrow in
                model.isWindowNarrow = isNarrow
            }
        }
        .ignoresSafeArea(.container, edges: .top)
        .background(JGColor.bgBase)
        .background(SidebarWindowLink(peek: peek))
        .onChange(of: model.isSidebarCollapsed, initial: true) { old, collapsed in
            fold(collapsed, animated: old != collapsed)
        }
        .onChange(of: peek.isOpen) { _, isOpen in
            if model.isSidebarCollapsed {
                animate { isPanelOpen = isOpen }
            }
        }
        .onChange(of: model.sidebarShowRequest) {
            if !SidebarWindowLink.widen(peek.window, animate: !reduceMotion) {
                NSSound.beep()
            }
        }
    }

    /// Folds the sidebar into its strip (the files take the room at once, under the panel closing over them) or
    /// unfolds it (the panel opens over the files, then they make room).
    private func fold(_ collapsed: Bool, animated: Bool) {
        if collapsed {
            reservesSidebar = false
            if animated {
                peek.suppressUntilExit()
            }
            animate(animated) { isPanelOpen = peek.isOpen }
            return
        }
        peek.close()
        guard animated, !isPanelOpen, !reduceMotion else {
            isPanelOpen = true
            reservesSidebar = true
            return
        }
        withAnimation(sidebarSpring) {
            isPanelOpen = true
        } completion: {
            if !model.isSidebarCollapsed {
                reservesSidebar = true
            }
        }
    }

    private func animate(_ animated: Bool = true, _ change: () -> Void) {
        if animated, !reduceMotion {
            withAnimation(sidebarSpring, change)
        } else {
            change()
        }
    }

    private var sidebarSpring: Animation {
        .spring(response: JGMetrics.sidebarSpringResponse, dampingFraction: JGMetrics.sidebarSpringDamping)
    }

    /// The columns' widths in a window `width` wide.
    private struct Columns {
        /// The files leave the sidebar its width; otherwise only the strip's (D-128).
        let docked: Bool
        /// The docked sidebar's width, or the strip's.
        let sidebar: CGFloat
        /// The right place's width; 0 when it is empty.
        let right: CGFloat
        /// The sidebar's width when it slides out over the files.
        let peek: CGFloat
    }

    private func layout(width: CGFloat) -> Columns {
        let docked = reservesSidebar
        let right = previewWidth(in: width, collapsed: !docked)
        let sidebar = docked ? sidebarWidth(in: width, preview: right) : JGMetrics.sidebarStripWidth
        let peek = max(JGMetrics.sidebarMinWidth, min(model.state.sidebarWidth, width - JGMetrics.libraryPaneMinWidth))
        return Columns(docked: docked, sidebar: sidebar, right: right, peek: peek)
    }

    private func columns(width: CGFloat) -> some View {
        let columns = layout(width: width)
        return GeometryReader { area in
            row(columns, height: area.size.height)
        }
        .onChange(of: columns.peek, initial: true) { _, width in
            peek.width = width
        }
    }

    private func row(_ columns: Columns, height: CGFloat) -> some View {
        HStack(spacing: 0) {
            // The room the sidebar panel takes; the panel itself lies over it (and over the files when it is out).
            Color.clear.frame(width: columns.sidebar)
            VStack(spacing: 0) {
                // The window's buttons stand on the first pane's top bar when the sidebar is a strip.
                panes(leadingInset: columns.docked ? nil : WindowControlsRoom.shared.width - JGMetrics.sidebarStripWidth)
                if let module = shownModule(in: .bottom) {
                    JGHairline()
                        .overlay {
                            PaneResizeHandle(
                                width: model.state.bottomHeight, growsTowardLeading: true, isVertical: true, set: model.setBottomHeight
                            )
                        }
                    moduleView(module, slot: .bottom)
                        .frame(height: bottomHeight(in: height))
                }
            }
            if let module = shownModule(in: .right) {
                JGHairline(.vertical)
                    .overlay {
                        PaneResizeHandle(width: model.state.previewWidth, growsTowardLeading: true, set: model.setPreviewWidth)
                    }
                moduleView(module, slot: .right)
                    .frame(width: columns.right)
            }
        }
        .overlay(alignment: .leading) {
            SidebarPanel(
                model: model, target: (isSecondPaneActive ? secondPane : nil) ?? model, isCompact: !isPanelOpen,
                isDocked: columns.docked,
                width: isPanelOpen ? (columns.docked ? columns.sidebar : columns.peek) : JGMetrics.sidebarStripWidth,
                contentWidth: columns.docked ? columns.sidebar : columns.peek, peek: peek
            )
        }
    }

    private var reduceMotion: Bool {
        systemReduceMotion || reduceMotionOverride
    }

    /// The folded sidebar sliding out over the files (D-128).
    private var peek: SidebarPeek {
        model.sidebarPeek
    }

    private func panes(leadingInset: CGFloat?) -> some View {
        VStack(spacing: 0) {
            if let secondPane, model.state.splitMode != .off {
                SplitPanes(
                    isStacked: model.state.splitMode == .stacked, fraction: model.state.splitFraction, set: onSplitFraction
                ) {
                    LibraryPaneView(model: model, onOpen: onOpen, showsActiveEdge: !isSecondPaneActive)
                        .environment(\.topBarLeadingInset, leadingInset)
                } second: {
                    LibraryPaneView(model: secondPane, onOpen: onOpen, showsActiveEdge: isSecondPaneActive)
                }
            } else {
                LibraryPaneView(model: model, onOpen: onOpen)
                    .environment(\.topBarLeadingInset, leadingInset)
            }
        }
    }

    /// The module shown in a place (D-127), if it can show: the preview needs its model, the size map its model and no
    /// split view; neither shows before the library has a folder.
    private func shownModule(in slot: ModuleSlot) -> LibraryModule? {
        guard !model.roots.isEmpty, let module = model.state.module(in: slot) else { return nil }
        switch module {
        case .preview: return preview == nil ? nil : module
        case .sizeMap: return sizeMap == nil || model.state.splitMode != .off ? nil : module
        }
    }

    @ViewBuilder
    private func moduleView(_ module: LibraryModule, slot: ModuleSlot) -> some View {
        switch module {
        case .preview:
            if let preview {
                PreviewPane(preview: preview, library: model, pane: isSecondPaneActive ? secondPane : model, slot: slot)
            }
        case .sizeMap:
            if let sizeMap {
                SizeMapModule(model: sizeMap, library: model, slot: slot)
            }
        }
    }

    /// The place under the files: its chosen height, lower when the window leaves the files too little room.
    private func bottomHeight(in height: CGFloat) -> CGFloat {
        let room = height - JGMetrics.bottomModuleMinHeight
        return max(JGMetrics.bottomModuleMinHeight, min(model.state.bottomHeight, room))
    }

    /// The right place's chosen width, narrower when the window leaves the panes less than their minimum (D-111).
    private func previewWidth(in width: CGFloat, collapsed: Bool) -> CGFloat {
        guard shownModule(in: .right) != nil else { return 0 }
        let room = width - JGMetrics.libraryPaneMinWidth - (collapsed ? JGMetrics.sidebarStripWidth : JGMetrics.sidebarMinWidth)
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
