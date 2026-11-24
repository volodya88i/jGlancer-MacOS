import AppKit
import JGDesign
import SwiftUI

/// The draggable edge of a side pane (the preview pane's left edge, the sidebar's right edge, D-78): a resize
/// cursor on hover; the pane clamps and saves the width.
struct PaneResizeHandle: View {
    let width: Double
    /// True when dragging toward the leading edge widens the pane (a pane on the right), or toward the top heightens it.
    let growsTowardLeading: Bool
    /// The top edge of a pane under the files: dragged up and down, `width` is its height (D-127).
    var isVertical = false
    let set: (Double) -> Void
    @State private var startWidth: Double?

    var body: some View {
        Rectangle()
            .fill(Color.clear)
            .frame(width: isVertical ? nil : JGMetrics.resizeHandleWidth, height: isVertical ? JGMetrics.resizeHandleWidth : nil)
            .contentShape(Rectangle())
            .onHover { inside in
                if inside {
                    (isVertical ? NSCursor.resizeUpDown : NSCursor.resizeLeftRight).push()
                } else {
                    NSCursor.pop()
                }
            }
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = startWidth ?? width
                        startWidth = start
                        let travel = isVertical ? drag.translation.height : drag.translation.width
                        set(start + (growsTowardLeading ? -1 : 1) * travel)
                    }
                    .onEnded { _ in startWidth = nil }
            )
            .accessibilityHidden(true)
    }
}
