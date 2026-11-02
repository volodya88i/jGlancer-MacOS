import AppKit

/// `-JGFilmstripRevealCheck <folder>` with `-JGOpen <file>` and the automatic filmstrip: moves the pointer (synthetic
/// events) to the bottom of the viewer, snapshots `reveal-near.png`, moves it to the middle, waits past the hide
/// delay and snapshots `reveal-away.png`.
@MainActor
enum FilmstripRevealCheck {
    static func run(window: NSWindow?, folder: URL) async {
        guard let window, let content = window.contentView else { return }
        try? await Task.sleep(for: .milliseconds(800))
        let height = content.bounds.height
        move(window, to: CGPoint(x: content.bounds.midX, y: height * 0.5))
        move(window, to: CGPoint(x: content.bounds.midX, y: 30))
        // Within the hide delay: the real pointer, wherever it rests, may move the strip away afterwards.
        try? await Task.sleep(for: .milliseconds(350))
        DeveloperHooks.snapshot(window, to: folder.appendingPathComponent("reveal-near.png"))
        move(window, to: CGPoint(x: content.bounds.midX, y: height * 0.5))
        try? await Task.sleep(for: .milliseconds(1200))
        DeveloperHooks.snapshot(window, to: folder.appendingPathComponent("reveal-away.png"))
    }

    /// A mouse move at `point` (window coordinates, origin bottom-left).
    private static func move(_ window: NSWindow, to point: CGPoint) {
        guard let event = NSEvent.mouseEvent(
            with: .mouseMoved, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 0, pressure: 0
        ) else { return }
        window.acceptsMouseMovedEvents = true
        window.contentView?.mouseMoved(with: event)
    }
}
