import AppKit
import JGDesign
import SwiftUI

/// The draggable edge of a side pane (the preview pane's left edge, the sidebar's right edge, D-78): a resize
/// cursor on hover; the pane clamps and saves the width.
struct PaneResizeHandle: View {
    let width: Double
    /// True when dragging toward the leading edge widens the pane (a pane on the right).
    let growsTowardLeading: Bool
    let set: (Double) -> Void
    @State private var startWidth: Double?

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: JGMetrics.resizeHandleWidth)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    NSCursor.resizeLeftRight.push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = startWidth ?? width
                        startWidth = start
                        set(start + (growsTowardLeading ? -1 : 1) * drag.translation.width)
                    }
                    .onEnded { _ in startWidth = nil }
            )
            .accessibilityHidden(true)
    }
}
