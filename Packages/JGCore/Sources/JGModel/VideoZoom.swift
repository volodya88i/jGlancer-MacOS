import CoreGraphics

/// Zoom and pan of a video picture (D-80, W-65): the picture's frame scaled 1…`maximum`× around a point and moved
/// by drags, always covering the view (no empty edge is dragged in). Scale 1 is fit.
public struct VideoZoom: Equatable, Sendable {
    public static let maximum: CGFloat = 8

    public private(set) var scale: CGFloat = 1
    /// The scaled frame's origin in the view (≤ 0 on both axes).
    public private(set) var origin: CGPoint = .zero

    public init() {}

    public var isFit: Bool {
        scale <= 1
    }

    /// The picture's frame in `bounds`.
    public func frame(in bounds: CGRect) -> CGRect {
        CGRect(x: bounds.minX + origin.x, y: bounds.minY + origin.y, width: bounds.width * scale, height: bounds.height * scale)
    }

    /// Zooms by `factor` keeping the picture under `point` (view coordinates) where it is.
    public mutating func zoom(by factor: CGFloat, at point: CGPoint, in bounds: CGRect) {
        guard factor > 0, factor.isFinite else { return }
        let newScale = min(max(scale * factor, 1), Self.maximum)
        let local = CGPoint(x: point.x - bounds.minX, y: point.y - bounds.minY)
        let ratio = newScale / scale
        origin = CGPoint(x: local.x - (local.x - origin.x) * ratio, y: local.y - (local.y - origin.y) * ratio)
        scale = newScale
        clamp(in: bounds)
    }

    public mutating func pan(by delta: CGVector, in bounds: CGRect) {
        origin = CGPoint(x: origin.x + delta.dx, y: origin.y + delta.dy)
        clamp(in: bounds)
    }

    public mutating func reset() {
        scale = 1
        origin = .zero
    }

    /// Keeps the frame over the whole view (after a pan, a zoom or a resize).
    public mutating func clamp(in bounds: CGRect) {
        let width = bounds.width * scale
        let height = bounds.height * scale
        origin = CGPoint(
            x: min(max(origin.x, bounds.width - width), 0),
            y: min(max(origin.y, bounds.height - height), 0)
        )
    }
}
