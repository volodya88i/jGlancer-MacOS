import os

/// A small lock-protected value (`Synchronization.Mutex` needs macOS 15).
final class Mutex<Value: Sendable>: Sendable {
    private let lock: OSAllocatedUnfairLock<Value>

    init(_ value: Value) {
        lock = OSAllocatedUnfairLock(initialState: value)
    }

    func withLock<Result: Sendable>(_ body: @Sendable (inout Value) -> Result) -> Result {
        lock.withLock(body)
    }
}
