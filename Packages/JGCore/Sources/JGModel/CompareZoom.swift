import CoreGraphics

/// Zoom and pan of one side of Compare (W-77), kept as fractions so that two photos of different sizes linked to the
/// same value show the same part: `scale` is relative to fit (1 = fit), `center` is the point of the picture at the
/// middle of the view, as a fraction of its width and height.
public struct CompareZoom: Equatable, Sendable {
    /// The deepest zoom, relative to fit.
    public static let maximum: CGFloat = 32

    public private(set) var scale: CGFloat = 1
    public private(set) var center = CGPoint(x: 0.5, y: 0.5)

    public init() {}

    public var isFit: Bool {
        scale <= 1.001
    }

    /// The picture's size at fit in `bounds`: as large as fits, never above `actualSize` (one image pixel per
    /// device pixel, in points).
    public static func fitSize(of actualSize: CGSize, in bounds: CGSize) -> CGSize {
        guard actualSize.width > 0, actualSize.height > 0, bounds.width > 0, bounds.height > 0 else { return .zero }
        let factor = min(1, bounds.width / actualSize.width, bounds.height / actualSize.height)
        return CGSize(width: actualSize.width * factor, height: actualSize.height * factor)
    }

    /// The scale that shows `actualSize` at 100 %.
    public static func actualScale(of actualSize: CGSize, in bounds: CGSize) -> CGFloat {
        let fit = fitSize(of: actualSize, in: bounds)
        return fit.width > 0 ? actualSize.width / fit.width : 1
    }

    /// The picture's frame in `bounds`: centered while smaller than the view, otherwise placed by `center` and kept
    /// over the whole view (no empty edge is dragged in).
    public func frame(of actualSize: CGSize, in bounds: CGRect) -> CGRect {
        let fit = Self.fitSize(of: actualSize, in: bounds.size)
        let size = CGSize(width: fit.width * scale, height: fit.height * scale)
        let point = Self.clamped(center, size: size, in: bounds.size)
        return CGRect(
            x: bounds.midX - point.x * size.width, y: bounds.midY - point.y * size.height,
            width: size.width, height: size.height
        )
    }

    /// Zooms to `newScale` keeping the picture under `point` (view coordinates) where it is.
    public mutating func zoom(to newScale: CGFloat, at point: CGPoint?, actualSize: CGSize, in bounds: CGRect) {
        let target = min(max(newScale, 1), Self.maximum)
        let before = frame(of: actualSize, in: bounds)
        guard before.width > 0, before.height > 0 else { return }
        let anchor = point ?? CGPoint(x: bounds.midX, y: bounds.midY)
        // The picture's fraction under the anchor stays under it.
        let fraction = CGPoint(x: (anchor.x - before.minX) / before.width, y: (anchor.y - before.minY) / before.height)
        let ratio = target / scale
        let width = before.width * ratio
        let height = before.height * ratio
        center = CGPoint(
            x: fraction.x - (anchor.x - bounds.midX) / width,
            y: fraction.y - (anchor.y - bounds.midY) / height
        )
        scale = target
        clamp(actualSize: actualSize, in: bounds)
    }

    public mutating func zoom(by factor: CGFloat, at point: CGPoint?, actualSize: CGSize, in bounds: CGRect) {
        guard factor > 0, factor.isFinite else { return }
        zoom(to: scale * factor, at: point, actualSize: actualSize, in: bounds)
    }

    /// Moves the picture by `delta` points.
    public mutating func pan(by delta: CGVector, actualSize: CGSize, in bounds: CGRect) {
        let size = frame(of: actualSize, in: bounds).size
        guard size.width > 0, size.height > 0 else { return }
        center = CGPoint(x: center.x - delta.dx / size.width, y: center.y - delta.dy / size.height)
        clamp(actualSize: actualSize, in: bounds)
    }

    public mutating func reset() {
        scale = 1
        center = CGPoint(x: 0.5, y: 0.5)
    }

    private mutating func clamp(actualSize: CGSize, in bounds: CGRect) {
        let fit = Self.fitSize(of: actualSize, in: bounds.size)
        center = Self.clamped(center, size: CGSize(width: fit.width * scale, height: fit.height * scale), in: bounds.size)
    }

    /// `center` kept so the picture covers the view on each axis where it is larger, and centered where not.
    private static func clamped(_ center: CGPoint, size: CGSize, in bounds: CGSize) -> CGPoint {
        func axis(_ value: CGFloat, _ length: CGFloat, _ room: CGFloat) -> CGFloat {
            guard length > room, length > 0 else { return 0.5 }
            let half = room / 2 / length
            return min(max(value, half), 1 - half)
        }
        return CGPoint(x: axis(center.x, size.width, bounds.width), y: axis(center.y, size.height, bounds.height))
    }
}
