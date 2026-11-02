import Testing
@testable import JGActions

struct ConflictPolicyTests {
    @Test func rawValuesAreStable() {
        #expect(ConflictPolicy.allCases.map(\.rawValue) == ["skip", "replace", "keepBoth"])
    }
}
