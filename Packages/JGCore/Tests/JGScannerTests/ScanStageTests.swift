import Testing
@testable import JGScanner

struct ScanStageTests {
    @Test func stagesAreOrderedByLatency() {
        #expect(ScanStage.allCases.sorted() == [.enumeration, .metadata, .derivatives])
        #expect(ScanStage.enumeration < ScanStage.metadata)
    }
}
