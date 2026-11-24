/// Playing a folded image sequence in the previews (W-86): frames advance at `framesPerSecond` from the frame shown
/// and stop at the last. A frame whose picture is not ready is skipped instead of slowing the clock.
public struct SequencePlayback: Equatable, Sendable {
    public static let framesPerSecond = 24.0

    public let frameCount: Int
    /// The frame shown.
    public private(set) var index = 0
    public private(set) var isPlaying = false
    /// Where play started: the frame and the clock time.
    private var startIndex = 0
    private var startTime = 0.0

    public init(frameCount: Int) {
        self.frameCount = max(1, frameCount)
    }

    public var isAtEnd: Bool {
        index >= frameCount - 1
    }

    /// Dragging the timeline: the frame under the pointer; play stops.
    public mutating func scrub(to frame: Int) {
        isPlaying = false
        index = min(max(frame, 0), frameCount - 1)
    }

    /// Starts from the frame shown (from the first when at the end) at clock time `now`.
    public mutating func play(at now: Double) {
        if isAtEnd {
            index = 0
        }
        isPlaying = true
        startIndex = index
        startTime = now
    }

    public mutating func pause() {
        isPlaying = false
    }

    /// The frame due at `now`; play stops at the last frame.
    public func due(at now: Double) -> Int {
        guard isPlaying else { return index }
        let elapsed = Int(((now - startTime) * Self.framesPerSecond).rounded(.down))
        return min(startIndex + max(elapsed, 0), frameCount - 1)
    }

    /// A clock tick: shows the frame due if `isReady(frame)`, else keeps the frame shown (the clock goes on). The
    /// last frame is always shown when its time comes (play ends there). Returns whether the frame shown changed.
    @discardableResult
    public mutating func tick(at now: Double, isReady: (Int) -> Bool) -> Bool {
        guard isPlaying else { return false }
        let due = due(at: now)
        if due >= frameCount - 1 {
            isPlaying = false
            defer { index = due }
            return due != index
        }
        guard due != index, isReady(due) else { return false }
        index = due
        return true
    }
}
