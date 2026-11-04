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

/// "Drag the file out" (D-123): a sheet open at its top-right corner with an arrow leaving it diagonally, drawn in
/// the strokes of the players' other drawn glyphs and kept inside a body-text symbol's box.
struct DragOutIcon: View {
    private static let side: CGFloat = 15
    /// How far in from the box the strokes run, so their round ends stay inside it.
    private static let inset: CGFloat = 1.5
    /// The sheet's side; the arrow leaves its open top-right corner for the box's corner.
    private static let sheet: CGFloat = 9.5
    /// Where the sheet's top and right edges stop short of its corner.
    private static let gap: CGFloat = 4
    private static let head: CGFloat = 4

    var body: some View {
        let low = Self.inset
        let high = Self.side - Self.inset
        let sheetTop = high - Self.sheet
        let sheetRight = low + Self.sheet
        ZStack {
            Path { path in
                path.move(to: CGPoint(x: sheetRight - Self.gap, y: sheetTop))
                path.addLine(to: CGPoint(x: low, y: sheetTop))
                path.addLine(to: CGPoint(x: low, y: high))
                path.addLine(to: CGPoint(x: sheetRight, y: high))
                path.addLine(to: CGPoint(x: sheetRight, y: sheetTop + Self.gap))
            }
            .stroke(style: Self.stroke)
            Path { path in
                path.move(to: CGPoint(x: (low + sheetRight) / 2, y: (sheetTop + high) / 2))
                path.addLine(to: CGPoint(x: high, y: low))
                path.move(to: CGPoint(x: high - Self.head, y: low))
                path.addLine(to: CGPoint(x: high, y: low))
                path.addLine(to: CGPoint(x: high, y: low + Self.head))
            }
            .stroke(style: Self.stroke)
        }
        .frame(width: Self.side, height: Self.side)
        .accessibilityHidden(true)
    }

    private static let stroke = StrokeStyle(lineWidth: JGMetrics.selectionEdgeWidth * 0.75, lineCap: .round, lineJoin: .round)
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
