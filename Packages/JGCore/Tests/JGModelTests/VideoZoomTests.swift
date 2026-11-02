import CoreGraphics
import Testing
@testable import JGModel

struct VideoZoomTests {
    let bounds = CGRect(x: 0, y: 0, width: 200, height: 100)

    @Test func zoomsAroundThePointAndStaysWithinLimits() {
        var zoom = VideoZoom()
        #expect(zoom.isFit)
        zoom.zoom(by: 2, at: CGPoint(x: 50, y: 50), in: bounds)
        #expect(zoom.scale == 2)
        #expect(zoom.frame(in: bounds) == CGRect(x: -50, y: -50, width: 400, height: 200)) // (50, 50) stays put
        zoom.zoom(by: 100, at: .zero, in: bounds)
        #expect(zoom.scale == VideoZoom.maximum)
        zoom.zoom(by: 0.001, at: .zero, in: bounds)
        #expect(zoom.isFit)
        #expect(zoom.frame(in: bounds) == bounds)
    }

    @Test func panningNeverShowsAnEdge() {
        var zoom = VideoZoom()
        zoom.pan(by: CGVector(dx: 30, dy: 30), in: bounds)
        #expect(zoom.origin == .zero) // at fit nothing moves
        zoom.zoom(by: 2, at: CGPoint(x: 100, y: 50), in: bounds)
        zoom.pan(by: CGVector(dx: 1000, dy: 0), in: bounds)
        #expect(zoom.origin.x == 0)
        zoom.pan(by: CGVector(dx: -1000, dy: -1000), in: bounds)
        #expect(zoom.origin == CGPoint(x: -200, y: -100))
        zoom.reset()
        #expect(zoom == VideoZoom())
    }
}
