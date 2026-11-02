import CoreGraphics

/// Where the grid loads thumbnails ahead of the screen (D-81). While scrolling, the speed
/// predicts where the screen will be `lookahead` seconds later; that screen and the strip just past the edge in the
/// direction of travel load next, and the tiles in between, which only fly past, are never asked for. At rest, a
/// screen above and below loads after the visible tiles. Offsets grow downwards.
public struct ScrollPrefetch: Equatable, Sendable {
    public static let lookahead = 0.4
    /// Quiet this long, the scroll counts as stopped.
    public static let settleDelay = 0.15

    /// Points per second, positive downwards; 0 at rest.
    public private(set) var velocity: Double = 0
    private var lastOffset: Double?
    private var lastTime: Double?

    public init() {}

    public var isScrolling: Bool {
        velocity != 0
    }

    /// The view scrolled to `offset` at `time` (seconds).
    public mutating func moved(to offset: Double, at time: Double) {
        if let lastOffset, let lastTime, time > lastTime {
            let instant = (offset - lastOffset) / (time - lastTime)
            // Smoothed, so one uneven frame does not swing the prediction.
            velocity = velocity == 0 ? instant : velocity * 0.6 + instant * 0.4
        }
        lastOffset = offset
        lastTime = time
    }

    public mutating func stopped() {
        velocity = 0
        lastOffset = nil
        lastTime = nil
    }

    /// The areas to load after the visible tiles, within the content.
    public func aheadRects(visible: CGRect, contentHeight: CGFloat) -> [CGRect] {
        let content = CGRect(x: visible.minX, y: 0, width: visible.width, height: max(contentHeight, visible.maxY))
        guard isScrolling else {
            return [visible.insetBy(dx: 0, dy: -visible.height).intersection(content)].filter { !$0.isEmpty }
        }
        let shift = CGFloat(velocity * Self.lookahead)
        let predicted = visible.offsetBy(dx: 0, dy: shift)
        let half = visible.height / 2
        let strip = velocity > 0
            ? CGRect(x: visible.minX, y: visible.maxY, width: visible.width, height: half)
            : CGRect(x: visible.minX, y: visible.minY - half, width: visible.width, height: half)
        return [strip, predicted].map { $0.intersection(content) }.filter { !$0.isEmpty }
    }
}
