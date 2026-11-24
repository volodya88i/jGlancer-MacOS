import AppKit
import JGDesign
import SwiftUI

/// The sidebar as one panel (D-128): docked beside the files, folded into its strip, or out over the files from the
/// strip. It is the same view at every width: unfolding moves its icons to their places and brings the names in, so the
/// strip visibly opens rather than a second panel coming in. Over the files it casts a shadow; docked, its edge drags.
struct SidebarPanel: View {
    let model: LibraryModel
    /// The pane a click shows a folder or album in (D-89).
    let target: LibraryModel
    /// The strip: icons only.
    let isCompact: Bool
    /// Beside the files (the files leave it room); otherwise it lies over them.
    let isDocked: Bool
    let width: CGFloat
    /// The unfolded width: the content is laid out at it also while folded, so unfolding moves things rather than
    /// squeezing them.
    let contentWidth: CGFloat
    let peek: SidebarPeek
    @State private var isDropTarget = false

    var body: some View {
        SidebarView(model: model, target: target, toggleRole: isDocked ? .hide : .keepOpen, compact: isCompact)
            .environment(\.sidebarRowWidth, contentWidth - 2 * JGSpacing.xs)
            .frame(width: contentWidth)
            .frame(width: width, alignment: .leading)
            .clipped()
            // Clipping hides what lies beyond the visible width but leaves it hit-testable: the pointer, clicks and the
            // scroll wheel over the files beside the strip must reach the files, not the folded panel's content.
            .contentShape(Rectangle())
            .overlay(alignment: .trailing) {
                // On the strip the top bar runs on over it, so its edge starts under the bar.
                JGHairline(.vertical)
                    .padding(.top, isCompact ? JGMetrics.barHeight + JGMetrics.outlineWidth : 0)
            }
            .background {
                Rectangle()
                    .fill(JGColor.bgPanel)
                    .shadow(
                        color: .black.opacity(isDocked || isCompact ? 0 : JGMetrics.sidebarPeekShadowOpacity),
                        radius: JGMetrics.sidebarPeekShadowRadius
                    )
            }
            .overlay(alignment: .trailing) {
                if isDocked, !isCompact {
                    PaneResizeHandle(width: width, growsTowardLeading: false, set: model.setSidebarWidth)
                }
            }
            .onContinuousHover(perform: hover)
            // Files dragged over the strip's free part open it, to be dropped on a folder, an album or the Trash.
            .onDrop(of: [.fileURL], isTargeted: Binding(get: { isDropTarget }, set: { isTargeted in
                isDropTarget = isTargeted
                if isTargeted, isCompact, !isDocked {
                    peek.open()
                }
            })) { _ in false }
    }

    /// The pointer on the folded sidebar: resting under the top bar and the Show Sidebar button opens it; once open,
    /// all of it keeps it open.
    private func hover(_ phase: HoverPhase) {
        guard !isDocked else { return }
        switch phase {
        case let .active(point):
            let opensHere = point.y > JGMetrics.barHeight + JGMetrics.controlHeightCompact
            peek.pointer(inPanel: true, onTrigger: peek.isOpen || opensHere)
        case .ended:
            peek.pointer(inPanel: false, onTrigger: false)
        }
    }
}

/// The sidebar's fold button (D-128): Hide Sidebar on the docked sidebar, Keep Sidebar Open on the one over the files,
/// Show Sidebar on the strip.
struct SidebarToggleButton: View {
    enum Role {
        case hide, keepOpen, show
    }

    let role: Role
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "sidebar.left")
                .font(.system(size: JGTextStyle.body.size))
                .foregroundStyle(JGColor.textSecondary)
                .frame(width: JGMetrics.controlHeightCompact, height: JGMetrics.controlHeightCompact)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }

    private var label: Text {
        switch role {
        case .hide: Text("Hide Sidebar (⌥⌘S)", comment: "Sidebar: the button that folds it into a strip")
        case .keepOpen: Text("Keep Sidebar Open (⌥⌘S)", comment: "Sidebar over the files: the button that docks it")
        case .show: Text("Show Sidebar (⌥⌘S)", comment: "Folded sidebar: the button that brings it back")
        }
    }
}

/// Hands the hosting window to `peek` and widens it when the sidebar is asked back in a window too narrow for it.
struct SidebarWindowLink: NSViewRepresentable {
    let peek: SidebarPeek

    final class Probe: NSView {
        weak var peek: SidebarPeek?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            peek?.window = window
        }
    }

    func makeNSView(context _: Context) -> Probe {
        let probe = Probe()
        probe.peek = peek
        return probe
    }

    func updateNSView(_ probe: Probe, context _: Context) {
        probe.peek = peek
        if peek.window == nil {
            peek.window = probe.window
        }
    }

    /// Widens `window` to the width the sidebar needs, keeping it on its screen; false when the screen is too narrow.
    @MainActor
    static func widen(_ window: NSWindow?, animate: Bool) -> Bool {
        guard let window, let screen = window.screen?.visibleFrame else { return false }
        let width = JGMetrics.sidebarAutoCollapseWidth + (window.frame.width - window.contentLayoutRect.width)
        guard width <= screen.width else { return false }
        var frame = window.frame
        frame.size.width = max(frame.width, width)
        frame.origin.x = min(frame.minX, screen.maxX - frame.width)
        window.setFrame(frame, display: true, animate: animate)
        return true
    }
}
