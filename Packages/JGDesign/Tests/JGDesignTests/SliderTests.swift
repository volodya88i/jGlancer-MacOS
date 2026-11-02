import AppKit
import CoreGraphics
import Testing
@testable import JGDesign

@MainActor
struct SliderTests {
    private func slider() -> SliderView {
        let view = SliderView(frame: NSRect(x: 0, y: 0, width: 240, height: 28))
        view.range = 80 ... 320
        view.step = 20
        view.value = 160
        return view
    }

    private func scroll(_ view: SliderView, vertical: Int32, horizontal: Int32 = 0, precise: Bool, shift: Bool = false) throws {
        let event = try #require(CGEvent(
            scrollWheelEvent2Source: nil, units: precise ? .pixel : .line, wheelCount: 2,
            wheel1: vertical, wheel2: horizontal, wheel3: 0
        ))
        if shift {
            event.flags = .maskShift
        }
        event.setIntegerValueField(.scrollWheelEventIsContinuous, value: precise ? 1 : 0)
        try view.scrollWheel(with: #require(NSEvent(cgEvent: event)))
    }

    @Test func dragsNeverMoveTheWindow() {
        #expect(!slider().mouseDownCanMoveWindow)
        #expect(slider().acceptsFirstMouse(for: nil))
    }

    @Test func clickAndDragSetTheValueContinuously() throws {
        let view = slider()
        var reported: [Double] = []
        view.onChange = { reported.append($0) }
        let down = try #require(NSEvent.mouseEvent(
            with: .leftMouseDown, location: NSPoint(x: 60, y: 10), modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        view.mouseDown(with: down)
        #expect(view.value == 140) // 80 + 60/240 × 240
        let drag = try #require(NSEvent.mouseEvent(
            with: .leftMouseDragged, location: NSPoint(x: 400, y: 10), modifierFlags: [], timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        view.mouseDragged(with: drag)
        #expect(view.value == 320)
        #expect(reported == [140, 320])
    }

    @Test func trackpadScrollZoomsBothWays() throws {
        let view = slider()
        try scroll(view, vertical: 30, precise: true)
        let afterUp = view.value
        #expect(afterUp > 160)
        try scroll(view, vertical: -60, precise: true)
        #expect(view.value < afterUp)
    }

    @Test func mouseWheelStepsAndValuesStayInRange() throws {
        let view = slider()
        try scroll(view, vertical: 1, precise: false)
        #expect(view.value == 164) // a fifth of a tick
        for _ in 0 ..< 100 {
            try scroll(view, vertical: -1, precise: false)
        }
        #expect(view.value == 80)
    }

    @Test func shiftSnapsWheelAndDragToTicks() throws {
        let view = slider()
        try scroll(view, vertical: 1, precise: false)
        try scroll(view, vertical: 1, precise: false, shift: true)
        #expect(view.value == 180, "\(view.value)") // 164 → the next tick after 160
        let drag = try #require(NSEvent.mouseEvent(
            with: .leftMouseDragged, location: NSPoint(x: 61, y: 10), modifierFlags: .shift, timestamp: 0,
            windowNumber: 0, context: nil, eventNumber: 0, clickCount: 1, pressure: 1
        ))
        view.mouseDragged(with: drag)
        #expect(view.value == 140) // 141 snapped
        #expect(view.focusRingType == .none)
    }

    @Test func accessibilityAdjustsByStep() {
        let view = slider()
        #expect(view.accessibilityRole() == .slider)
        #expect(view.accessibilityPerformIncrement())
        #expect(view.value == 180)
        #expect(view.accessibilityPerformDecrement())
        #expect(view.value == 160)
    }
}
