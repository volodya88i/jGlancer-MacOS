import SwiftUI

/// The design system's rounded rectangle: continuous corners at a token radius.
public struct JGShape: InsettableShape {
    /// Radius tokens (JGMetrics).
    public enum Size: Sendable {
        case small
        case medium
        case large

        var radius: CGFloat {
            switch self {
            case .small: JGMetrics.radiusSmall
            case .medium: JGMetrics.radiusMedium
            case .large: JGMetrics.radiusLarge
            }
        }
    }

    private let size: Size
    private var inset: CGFloat = 0

    /// Creates the shape for a radius token.
    public init(_ size: Size) {
        self.size = size
    }

    public func path(in rect: CGRect) -> Path {
        RoundedRectangle(cornerRadius: max(0, size.radius - inset), style: .continuous)
            .path(in: rect.insetBy(dx: inset, dy: inset))
    }

    public func inset(by amount: CGFloat) -> JGShape {
        var copy = self
        copy.inset += amount
        return copy
    }
}
