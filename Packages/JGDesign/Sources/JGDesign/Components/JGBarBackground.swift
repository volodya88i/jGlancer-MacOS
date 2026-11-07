import SwiftUI

/// The background of a bar that content scrolls under, as Finder's toolbar and path bar (D-114): what lies beneath,
/// blurred, under the bar's color at `JGMetrics.barGlassTintOpacity`. The plain color with frosted glass off
/// (`jgFrostedGlass`), Reduce Transparency or Increase Contrast.
struct JGBarBackground<Fill: ShapeStyle, Outline: Shape>: ViewModifier {
    let fill: Fill
    let shape: Outline
    var tintOpacity = JGMetrics.barGlassTintOpacity
    @Environment(\.jgFrostedGlass) private var isFrosted
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.background {
            if isFrosted, !reduceTransparency, contrast != .increased {
                ZStack {
                    // The thinnest material, lightly tinted: more see-through, a softer blur (D-115).
                    shape.fill(.ultraThinMaterial)
                    shape.fill(fill).opacity(tintOpacity)
                }
            } else {
                shape.fill(fill)
            }
        }
    }
}

public extension View {
    /// A bar over scrolling content: frosted glass tinted with `fill`, or `fill` alone (D-114).
    func jgBarBackground(_ fill: some ShapeStyle) -> some View {
        modifier(JGBarBackground(fill: fill, shape: Rectangle()))
    }

    /// The same glass in `shape`, its color covering `tintOpacity` of what lies beneath: the floating status bubble
    /// (D-116).
    func jgBarBackground(
        _ fill: some ShapeStyle, in shape: some Shape, tintOpacity: Double = JGMetrics.barGlassTintOpacity
    ) -> some View {
        modifier(JGBarBackground(fill: fill, shape: shape, tintOpacity: tintOpacity))
    }
}
