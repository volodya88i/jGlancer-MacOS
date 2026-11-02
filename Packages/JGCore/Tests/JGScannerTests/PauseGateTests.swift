import Testing
@testable import JGScanner

struct PauseGateTests {
    @Test func waitersGoOnWhenTheLastHoldIsReleased() async throws {
        let gate = PauseGate()
        await gate.waitWhileHeld() // nothing holds it: returns at once
        await gate.hold()
        await gate.hold()
        let waiter = Task { await gate.waitWhileHeld() }
        await gate.release()
        try await Task.sleep(for: .milliseconds(30))
        #expect(await gate.isHeld)
        await gate.release()
        await waiter.value
        #expect(await !gate.isHeld)
    }
}
