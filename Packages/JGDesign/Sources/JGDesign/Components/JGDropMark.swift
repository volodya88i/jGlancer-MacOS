import SwiftUI

/// Marks a row that takes a drop (D-110): an accent ring and a wash of the accent over it, fading in and out, with no
/// change of layout. Instant with Reduce Motion.
struct JGDropMark<Outline: InsettableShape>: ViewModifier {
    let isOn: Bool
    let shape: Outline
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            ZStack {
                shape.fill(JGColor.accent).opacity(JGMetrics.dropWashOpacity)
                shape.strokeBorder(JGColor.accent, lineWidth: JGMetrics.selectionEdgeWidth)
            }
            .opacity(isOn ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: JGMetrics.dropMarkFadeDuration), value: isOn)
            .allowsHitTesting(false)
        }
    }
}

public extension View {
    /// The drop mark of a sidebar row (D-110).
    func jgDropMark(_ isOn: Bool, in shape: some InsettableShape) -> some View {
        modifier(JGDropMark(isOn: isOn, shape: shape))
    }
}
