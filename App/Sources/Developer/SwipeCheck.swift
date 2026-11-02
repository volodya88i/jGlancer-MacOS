import AppKit

/// `-JGSwipeCheck <folder>` with `-JGOpen <photo or song>` (and `-JGSwipeInput drag|trackpad`): swipes left with
/// synthetic events sent to the view that takes clicks in the middle of the viewer, snapshots `swipe-mid.png` while
/// the content follows and `swipe-after.png` after the release, and logs the file index before and after.
@MainActor
enum SwipeCheck {
    static func run(appModel: AppModel, window: NSWindow?, folder: URL, input: String) async {
        guard let window, let content = window.contentView else { return }
        try? await Task.sleep(for: .milliseconds(800))
        let point = CGPoint(x: content.bounds.midX, y: content.bounds.midY)
        guard let target = content.hitTest(point) else { return }
        log("view under the pointer: \(type(of: target)), index before: \(index(appModel))")
        let steps = Int(content.bounds.width * 0.6 / 30)
        if input == "trackpad" {
            target.scrollWheel(with: scroll(phase: 1, delta: 0))
        } else if let down = mouse(.leftMouseDown, at: point, in: window, delta: 0) {
            target.mouseDown(with: down)
        }
        for step in 0 ..< steps {
            if input == "trackpad" {
                // Synthetic events are not marked as natural scrolling: a positive delta moves the content left.
                target.scrollWheel(with: scroll(phase: 2, delta: 30))
            } else if let drag = mouse(
                .leftMouseDragged,
                at: CGPoint(x: point.x - CGFloat(step + 1) * 30, y: point.y),
                in: window,
                delta: -30
            ) {
                target.mouseDragged(with: drag)
            }
            try? await Task.sleep(for: .milliseconds(30))
        }
        DeveloperHooks.snapshot(window, to: folder.appendingPathComponent("swipe-mid.png"))
        if input == "trackpad" {
            target.scrollWheel(with: scroll(phase: 4, delta: 0))
        } else if let up = mouse(.leftMouseUp, at: point, in: window, delta: 0) {
            target.mouseUp(with: up)
        }
        try? await Task.sleep(for: .milliseconds(900))
        DeveloperHooks.snapshot(window, to: folder.appendingPathComponent("swipe-after.png"))
        log("index after: \(index(appModel))")
    }

    private static func index(_ appModel: AppModel) -> Int {
        switch appModel.viewer {
        case let .photo(model): model.index
        case let .media(model): model.playback.queue.index
        case .compare: 0
        case nil: -1
        }
    }

    private static func mouse(_ type: CGEventType, at point: CGPoint, in window: NSWindow, delta: Int64) -> NSEvent? {
        let screenPoint = window.convertPoint(toScreen: point)
        let flipped = CGPoint(x: screenPoint.x, y: (NSScreen.screens.first?.frame.height ?? 0) - screenPoint.y)
        guard let event = CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: flipped, mouseButton: .left) else {
            return nil
        }
        event.setIntegerValueField(.mouseEventDeltaX, value: delta)
        event.setIntegerValueField(.mouseEventClickState, value: 1)
        return NSEvent(cgEvent: event)
    }

    /// A trackpad scroll event (continuous, so it has precise deltas) in `phase` (1 began, 2 changed, 4 ended).
    private static func scroll(phase: Int64, delta: Int32) -> NSEvent {
        let event = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: 0, wheel2: delta, wheel3: 0)
        event?.setIntegerValueField(.scrollWheelEventIsContinuous, value: 1)
        event?.setIntegerValueField(.scrollWheelEventScrollPhase, value: phase)
        return event.flatMap(NSEvent.init(cgEvent:)) ?? NSEvent()
    }

    private static func log(_ line: String) {
        FileHandle.standardError.write(Data("swipe check: \(line)\n".utf8))
    }
}
