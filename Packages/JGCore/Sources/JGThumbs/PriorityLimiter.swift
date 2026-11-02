import Foundation

/// Bounds concurrent work and hands free slots to the highest-priority waiter first. Background work takes at most
/// `backgroundCapacity` slots, so a long background queue trickles along without loading the CPU (D-81).
/// Waiters can be raised or lowered (a tile scrolls into view, or out of it) and cancelled.
actor PriorityLimiter {
    /// A slot taken by `acquire`; give it back with `release`.
    struct Slot: Sendable {
        let isBackground: Bool
    }

    private struct Waiter {
        let id: UUID
        var priority: ThumbnailPriority
        let order: Int
        let continuation: CheckedContinuation<Slot?, Never>
        let tag: AnyHashable?
    }

    private let capacity: Int
    private let backgroundCapacity: Int
    private var running = 0
    private var runningBackground = 0
    private var waiters: [Waiter] = []
    private var counter = 0

    init(capacity: Int, backgroundCapacity: Int = 1) {
        self.capacity = max(1, capacity)
        self.backgroundCapacity = max(1, min(backgroundCapacity, capacity))
    }

    /// Waits for a slot; nil if the task was cancelled while waiting (no slot taken).
    func acquire(priority: ThumbnailPriority, tag: AnyHashable? = nil) async -> Slot? {
        if Task.isCancelled {
            return nil
        }
        if waiters.isEmpty, canStart(priority) {
            return grant(priority)
        }
        let id = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                counter += 1
                waiters.append(Waiter(id: id, priority: priority, order: counter, continuation: continuation, tag: tag))
                if Task.isCancelled {
                    cancelWaiter(id)
                }
                // A free slot this waiter may take (background ones can wait while visible work could run).
                resumeNext()
            }
        } onCancel: {
            Task { await self.cancelWaiter(id) }
        }
    }

    /// Gives back a slot from `acquire`.
    func release(_ slot: Slot) {
        running -= 1
        if slot.isBackground {
            runningBackground -= 1
        }
        resumeNext()
    }

    /// Raises the priority of waiters with `tag` (never lowers it).
    func boost(tag: AnyHashable, to priority: ThumbnailPriority) {
        for index in waiters.indices where waiters[index].tag == tag && waiters[index].priority < priority {
            waiters[index].priority = priority
        }
    }

    /// Sets the priority of waiters with `tag`, up or down; work already running is not affected.
    func setPriority(tag: AnyHashable, to priority: ThumbnailPriority) {
        for index in waiters.indices where waiters[index].tag == tag {
            waiters[index].priority = priority
        }
        resumeNext()
    }

    /// Number of tasks currently holding a slot (for tests).
    var runningCount: Int {
        running
    }

    private func canStart(_ priority: ThumbnailPriority) -> Bool {
        running < capacity && (priority > .background || runningBackground < backgroundCapacity)
    }

    private func grant(_ priority: ThumbnailPriority) -> Slot {
        running += 1
        if priority == .background {
            runningBackground += 1
        }
        return Slot(isBackground: priority == .background)
    }

    private func cancelWaiter(_ id: UUID) {
        guard let index = waiters.firstIndex(where: { $0.id == id }) else { return }
        waiters.remove(at: index).continuation.resume(returning: nil)
    }

    private func resumeNext() {
        while running < capacity {
            // Highest priority first, FIFO within a priority; background only while its share is free.
            let best = waiters.indices.filter { canStart(waiters[$0].priority) }.max { lhs, rhs in
                let left = waiters[lhs]
                let right = waiters[rhs]
                return left.priority == right.priority ? left.order > right.order : left.priority < right.priority
            }
            guard let best else { return }
            let waiter = waiters.remove(at: best)
            waiter.continuation.resume(returning: grant(waiter.priority))
        }
    }
}
