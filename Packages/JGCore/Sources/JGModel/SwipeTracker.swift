/// Turns horizontal mouse drags and two-finger trackpad swipes into paging between files (docs/FEATURES.md §4.1,
/// §4.3). Travel is how far the content moved: negative = to the left, which brings the next file.
///
/// Instant mode pages once the travel passes `instantThreshold` (once per gesture). Animated mode lets the content
/// follow the pointer and decides on release: past `commitFraction` of the width, or a flick, completes the page;
/// otherwise the content springs back. Without a file in the travel's direction the content moves with resistance.
public struct SwipeTracker: Sendable {
    /// Travel that turns the page at once (instant mode), in points.
    public static let instantThreshold = 40.0
    /// Share of the width past which a released swipe completes (animated mode).
    public static let commitFraction = 0.2
    /// Speed, in points per second, of a flick that completes a short swipe.
    public static let flickSpeed = 600.0
    /// Share of the travel shown when there is no file in that direction.
    public static let edgeResistance = 0.25

    public let isAnimated: Bool
    public private(set) var travel = 0.0
    private var didPage = false

    public init(isAnimated: Bool) {
        self.isAnimated = isAnimated
    }

    /// +1 for the next file (content moved left), -1 for the previous one.
    public var direction: Int {
        travel < 0 ? 1 : -1
    }

    /// Adds travel. Instant mode returns the direction to page to, once per gesture, when allowed.
    public mutating func move(by delta: Double, canPage: (Int) -> Bool) -> Int? {
        travel += delta
        guard !isAnimated, !didPage, abs(travel) > Self.instantThreshold else { return nil }
        didPage = true
        return canPage(direction) ? direction : nil
    }

    /// Where the content sits while it follows the pointer (animated mode).
    public func offset(canPage: (Int) -> Bool) -> Double {
        canPage(direction) ? travel : travel * Self.edgeResistance
    }

    /// The release: the direction to complete the page to, or nil to spring back (and always nil when instant).
    /// `velocity` is the content's speed in points per second, negative to the left.
    public mutating func end(width: Double, velocity: Double, canPage: (Int) -> Bool) -> Int? {
        defer {
            travel = 0
            didPage = false
        }
        guard isAnimated, travel != 0 else { return nil }
        let isFar = abs(travel) > width * Self.commitFraction
        let isFlick = abs(velocity) > Self.flickSpeed && (velocity < 0) == (travel < 0)
        return (isFar || isFlick) && canPage(direction) ? direction : nil
    }
}
