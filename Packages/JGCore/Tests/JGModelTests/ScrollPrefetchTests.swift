import CoreGraphics
import Testing
@testable import JGModel

struct ScrollPrefetchTests {
    let screen = CGRect(x: 0, y: 1000, width: 800, height: 600)

    @Test func atRestAScreenAboveAndBelowLoads() {
        let prefetch = ScrollPrefetch()
        #expect(!prefetch.isScrolling)
        #expect(prefetch.aheadRects(visible: screen, contentHeight: 10000) == [CGRect(x: 0, y: 400, width: 800, height: 1800)])
    }

    @Test func aFastScrollLoadsWhereTheScreenWillBe() {
        var prefetch = ScrollPrefetch()
        prefetch.moved(to: 1000, at: 0)
        prefetch.moved(to: 1100, at: 0.01) // 10 000 pt/s downwards
        #expect(prefetch.velocity == 10000)
        let rects = prefetch.aheadRects(visible: screen, contentHeight: 100_000)
        #expect(rects.count == 2)
        #expect(rects[0] == CGRect(x: 0, y: 1600, width: 800, height: 300)) // the strip just below
        #expect(rects[1] == CGRect(x: 0, y: 5000, width: 800, height: 600)) // 0.4 s later
        // Near the end the prediction stays in the content.
        #expect(prefetch.aheadRects(visible: screen, contentHeight: 3000).allSatisfy { $0.maxY <= 3000 })
        prefetch.stopped()
        #expect(!prefetch.isScrolling)
    }

    @Test func scrollingUpLoadsAbove() {
        var prefetch = ScrollPrefetch()
        prefetch.moved(to: 1000, at: 0)
        prefetch.moved(to: 990, at: 0.01)
        let rects = prefetch.aheadRects(visible: screen, contentHeight: 100_000)
        #expect(rects[0].maxY == screen.minY)
        #expect(rects[1].minY == screen.minY - 400)
    }
}
