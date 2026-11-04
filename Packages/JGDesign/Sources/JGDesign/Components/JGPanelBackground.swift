import SwiftUI

public extension EnvironmentValues {
    /// Frosted glass behind floating panels and toasts (D-109); off: their plain fill. Root views set it from settings.
    @Entry var jgFrostedGlass = true
}

/// The background of a floating panel (toasts, progress cards; D-109): what the window draws behind it, blurred
/// live under the panel's color at `JGMetrics.panelGlassTintOpacity`. The plain color with the setting off, Reduce
/// Transparency or Increase Contrast.
struct JGPanelBackground<Fill: ShapeStyle, Outline: InsettableShape>: ViewModifier {
    let fill: Fill
    let shape: Outline
    @Environment(\.jgFrostedGlass) private var isFrosted
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorSchemeContrast) private var contrast

    func body(content: Content) -> some View {
        content.background {
            if isFrosted, !reduceTransparency, contrast != .increased {
                ZStack {
                    shape.fill(.regularMaterial)
                    shape.fill(fill).opacity(JGMetrics.panelGlassTintOpacity)
                }
            } else {
                shape.fill(fill)
            }
        }
    }
}

public extension View {
    /// A floating panel's background: frosted glass tinted with `fill`, or `fill` alone (D-109).
    func jgPanelBackground(_ fill: some ShapeStyle, in shape: some InsettableShape) -> some View {
        modifier(JGPanelBackground(fill: fill, shape: shape))
    }
}
