import JGDesign
import SwiftUI

/// "Fade the ends" (D-73): a level that rises, holds and falls over a faint baseline, at the size of a
/// body-text symbol.
struct FadeEdgesIcon: View {
    /// Where the rise ends and the fall starts, as fractions of the width.
    private static let shoulder: CGFloat = 0.3
    private static let size = CGSize(width: 16, height: 11)

    var body: some View {
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: 0, y: Self.size.height))
                path.addLine(to: CGPoint(x: Self.size.width, y: Self.size.height))
            }
            .stroke(style: StrokeStyle(lineWidth: JGMetrics.outlineWidth))
            .opacity(JGMetrics.placeholderOpacity)
            Path { path in
                path.move(to: CGPoint(x: 0, y: Self.size.height))
                path.addLine(to: CGPoint(x: Self.size.width * Self.shoulder, y: 0))
                path.addLine(to: CGPoint(x: Self.size.width * (1 - Self.shoulder), y: 0))
                path.addLine(to: CGPoint(x: Self.size.width, y: Self.size.height))
            }
            .stroke(style: StrokeStyle(lineWidth: JGMetrics.selectionEdgeWidth * 0.75, lineCap: .round, lineJoin: .round))
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .accessibilityHidden(true)
    }
}

/// A player button with a drawn icon instead of an SF Symbol (otherwise `ViewerIconButton`).
struct ViewerGlyphButton<Glyph: View>: View {
    let label: Text
    var isOn = false
    let action: () -> Void
    @ViewBuilder let glyph: Glyph

    var body: some View {
        Button(action: action) {
            glyph
                .foregroundStyle(isOn ? JGColor.accentText : JGColor.textPrimary)
                .frame(width: JGMetrics.controlHeight, height: JGMetrics.controlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .help(label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}
