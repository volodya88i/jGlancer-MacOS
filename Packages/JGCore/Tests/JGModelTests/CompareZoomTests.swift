import CoreGraphics
import Testing
@testable import JGModel

struct CompareZoomTests {
    private let bounds = CGRect(x: 0, y: 0, width: 400, height: 300)

    @Test func fitNeverEnlargesAndKeepsProportions() {
        #expect(CompareZoom.fitSize(of: CGSize(width: 800, height: 400), in: bounds.size) == CGSize(width: 400, height: 200))
        #expect(CompareZoom.fitSize(of: CGSize(width: 100, height: 50), in: bounds.size) == CGSize(width: 100, height: 50))
        #expect(CompareZoom.actualScale(of: CGSize(width: 800, height: 400), in: bounds.size) == 2)
        let frame = CompareZoom().frame(of: CGSize(width: 800, height: 400), in: bounds)
        #expect(frame == CGRect(x: 0, y: 50, width: 400, height: 200))
    }

    @Test func zoomKeepsThePointUnderThePointer() {
        var zoom = CompareZoom()
        let size = CGSize(width: 800, height: 600)
        let point = CGPoint(x: 100, y: 75)
        let before = zoom.frame(of: size, in: bounds)
        let fraction = (point.x - before.minX) / before.width
        zoom.zoom(by: 2, at: point, actualSize: size, in: bounds)
        let after = zoom.frame(of: size, in: bounds)
        #expect(zoom.scale == 2)
        #expect(abs((point.x - after.minX) / after.width - fraction) < 0.0001)
    }

    @Test func linkedFractionsShowTheSamePartOfDifferentSizes() {
        var zoom = CompareZoom()
        let big = CGSize(width: 4000, height: 3000)
        zoom.zoom(to: 4, at: CGPoint(x: 300, y: 100), actualSize: big, in: bounds)
        zoom.pan(by: CGVector(dx: -50, dy: 20), actualSize: big, in: bounds)
        // The same zoom on a smaller photo of the same shape puts the same fraction in the middle.
        let small = CGSize(width: 1000, height: 750)
        for size in [big, small] {
            let frame = zoom.frame(of: size, in: bounds)
            let middle = CGPoint(x: (bounds.midX - frame.minX) / frame.width, y: (bounds.midY - frame.minY) / frame.height)
            #expect(abs(middle.x - zoom.center.x) < 0.0001)
            #expect(abs(middle.y - zoom.center.y) < 0.0001)
        }
    }

    @Test func panStopsAtTheEdgesAndFitCenters() {
        var zoom = CompareZoom()
        let size = CGSize(width: 800, height: 600)
        zoom.pan(by: CGVector(dx: 500, dy: 0), actualSize: size, in: bounds)
        #expect(zoom.center == CGPoint(x: 0.5, y: 0.5))
        zoom.zoom(to: 2, at: nil, actualSize: size, in: bounds)
        zoom.pan(by: CGVector(dx: 5000, dy: -5000), actualSize: size, in: bounds)
        let frame = zoom.frame(of: size, in: bounds)
        #expect(frame.minX == 0)
        #expect(frame.maxY == bounds.maxY)
        zoom.zoom(to: 100, at: nil, actualSize: size, in: bounds)
        #expect(zoom.scale == CompareZoom.maximum)
        zoom.reset()
        #expect(zoom.isFit)
    }
}
