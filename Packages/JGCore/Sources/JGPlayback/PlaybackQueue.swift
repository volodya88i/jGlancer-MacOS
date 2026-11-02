/// The files a player moves through: the videos or the audio files of one folder (docs/ARCHITECTURE.md §8–9,
/// DECISIONS D-09), and the rules for previous, next and the end of an item. No wrap-around at the ends.
public struct PlaybackQueue: Equatable, Sendable {
    public private(set) var items: [PlaybackItem]
    public private(set) var index: Int

    /// Seconds into an item after which "previous" restarts it instead of going back.
    public static let restartThreshold = 3.0

    /// What happens when the current item plays to its end.
    public enum EndAction: Equatable, Sendable {
        /// Start the current item again (loop).
        case replay
        /// Move to the item at this index and play it.
        case advance(Int)
        /// Stay at the end, paused.
        case stop
    }

    /// What "previous" does.
    public enum PreviousAction: Equatable, Sendable {
        case restart
        /// Go to the item at this index.
        case move(Int)
    }

    public init(items: [PlaybackItem] = [], index: Int = 0) {
        self.items = items
        self.index = items.isEmpty ? 0 : min(max(index, 0), items.count - 1)
    }

    public var current: PlaybackItem? {
        items.indices.contains(index) ? items[index] : nil
    }

    public var count: Int {
        items.count
    }

    public var hasNext: Bool {
        index + 1 < items.count
    }

    public var hasPrevious: Bool {
        index > 0
    }

    /// Makes the item at `newIndex` current; returns false when it is out of range or already current.
    @discardableResult
    public mutating func select(_ newIndex: Int) -> Bool {
        guard items.indices.contains(newIndex), newIndex != index else { return false }
        index = newIndex
        return true
    }

    /// `loop` repeats the current item; `autoAdvance` continues with the next one (audio by default).
    public func endAction(loop: Bool, autoAdvance: Bool) -> EndAction {
        if loop {
            return .replay
        }
        return autoAdvance && hasNext ? .advance(index + 1) : .stop
    }

    /// Restarts the current item when playback is past `restartThreshold` or there is nothing before it.
    public func previousAction(currentTime: Double) -> PreviousAction {
        currentTime > Self.restartThreshold || !hasPrevious ? .restart : .move(index - 1)
    }

    /// Replaces the items (a folder listing arrived), keeping the item with `id` current when it is still there.
    public mutating func replaceItems(_ newItems: [PlaybackItem], keeping id: PlaybackItem.ID?) {
        let newIndex = id.flatMap { id in newItems.firstIndex { $0.id == id } } ?? 0
        self = PlaybackQueue(items: newItems, index: newIndex)
    }
}
