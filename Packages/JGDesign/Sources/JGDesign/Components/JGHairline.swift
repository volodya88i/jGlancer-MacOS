import SwiftUI

/// A one-device-pixel divider. Hairlines replace shadows everywhere (docs/DESIGN.md §2).
public struct JGHairline: View {
    /// Direction of the line.
    public enum Orientation: Sendable {
        case horizontal
        case vertical
    }

    private let orientation: Orientation
    private let color: JGColorToken
    @Environment(\.displayScale) private var displayScale

    /// Creates a hairline that stretches along `orientation`.
    public init(_ orientation: Orientation = .horizontal, color: JGColorToken = JGColor.lineHair) {
        self.orientation = orientation
        self.color = color
    }

    public var body: some View {
        let thickness = JGMetrics.hairline(displayScale: displayScale)
        Rectangle()
            .fill(color)
            .frame(
                width: orientation == .vertical ? thickness : nil,
                height: orientation == .horizontal ? thickness : nil
            )
            .accessibilityHidden(true)
    }
}

#Preview {
    HStack(spacing: JGSpacing.l) {
        JGHairline(.vertical)
        VStack(spacing: JGSpacing.l) {
            JGHairline()
            JGHairline(color: JGColor.lineStrong)
        }
    }
    .padding(JGSpacing.l)
    .frame(width: 240, height: 120)
    .background(JGColor.bgBase)
}
