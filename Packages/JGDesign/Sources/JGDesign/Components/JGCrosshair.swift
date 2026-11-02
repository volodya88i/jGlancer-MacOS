import SwiftUI

/// The decorative "+" mark placed at hairline intersections and selected frame corners (docs/DESIGN.md §6).
public struct JGCrosshair: View {
    private let color: JGColorToken

    /// Creates a crosshair, muted by default.
    public init(color: JGColorToken = JGColor.textTertiary) {
        self.color = color
    }

    public var body: some View {
        let size = JGMetrics.crosshairSize
        Path { path in
            path.move(to: CGPoint(x: size / 2, y: 0))
            path.addLine(to: CGPoint(x: size / 2, y: size))
            path.move(to: CGPoint(x: 0, y: size / 2))
            path.addLine(to: CGPoint(x: size, y: size / 2))
        }
        .stroke(color, lineWidth: JGMetrics.outlineWidth)
        .frame(width: size, height: size)
        .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: JGSpacing.l) {
        JGCrosshair()
        JGCrosshair(color: JGColor.accent)
    }
    .padding(JGSpacing.l)
    .background(JGColor.bgBase)
}
