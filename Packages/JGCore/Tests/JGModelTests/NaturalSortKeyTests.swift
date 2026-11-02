import Testing
@testable import JGModel

struct NaturalSortKeyTests {
    private func sorted(_ names: [String]) -> [String] {
        names.sorted { NaturalSortKey.make($0) < NaturalSortKey.make($1) }
    }

    @Test func numbersSortByValue() {
        #expect(sorted(["IMG_10.jpg", "IMG_2.jpg", "IMG_1.jpg"]) == ["IMG_1.jpg", "IMG_2.jpg", "IMG_10.jpg"])
        #expect(sorted(["track 100", "track 20", "track 3"]) == ["track 3", "track 20", "track 100"])
    }

    @Test func caseAndDiacriticsAreIgnored() {
        #expect(NaturalSortKey.make("Café.JPG") == NaturalSortKey.make("cafe.jpg"))
        #expect(sorted(["b.jpg", "A.jpg", "c.jpg"]) == ["A.jpg", "b.jpg", "c.jpg"])
    }

    @Test func decomposedAndComposedNamesShareAKey() {
        #expect(NaturalSortKey.make("cafe\u{0301}") == NaturalSortKey.make("caf\u{00E9}"))
    }

    @Test func leadingZerosDoNotChangeOrder() {
        #expect(sorted(["x010", "x9", "x0011"]) == ["x9", "x010", "x0011"])
    }
}
