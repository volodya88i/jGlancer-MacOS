import Testing
@testable import JGModel

struct DurationFormatTests {
    @Test(arguments: [
        (0.0, "0:00"), (2.4, "0:02"), (59.6, "1:00"), (125, "2:05"), (3600, "1:00:00"), (3723, "1:02:03"),
    ])
    func positionalTimeCodes(seconds: Double, expected: String) {
        #expect(DurationFormat.positional(seconds) == expected)
    }

    @Test func tenthsForSegmentEnds() {
        #expect(DurationFormat.tenths(62.34) == "1:02.3")
        #expect(DurationFormat.tenths(59.97) == "1:00.0")
        #expect(DurationFormat.tenths(0) == "0:00.0")
        #expect(DurationFormat.tenths(-1) == nil)
    }

    @Test func invalidDurationsHaveNoText() {
        #expect(DurationFormat.positional(-1) == nil)
        #expect(DurationFormat.positional(.nan) == nil)
        #expect(DurationFormat.positional(.infinity) == nil)
    }
}
