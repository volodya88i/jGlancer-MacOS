/// Lets foreground work pause background reading (D-82, W-74): while anything holds the gate, metadata
/// extraction waits before its next file. Every `hold` needs one `release`.
public actor PauseGate {
    private var holds = 0
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    public func hold() {
        holds += 1
    }

    public func release() {
        holds = max(0, holds - 1)
        if holds == 0 {
            let waiting = waiters
            waiters.removeAll()
            for waiter in waiting {
                waiter.resume()
            }
        }
    }

    public var isHeld: Bool {
        holds > 0
    }

    /// Returns at once when nothing holds the gate, else when it is released.
    public func waitWhileHeld() async {
        guard holds > 0 else { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}
