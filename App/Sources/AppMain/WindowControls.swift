import AppKit
import JGDesign
import SwiftUI

/// The window's close, minimize and zoom buttons centred on the top bar's line (D-114), as Finder's sit on its
/// toolbar: the title-bar strip is made as high as `JGMetrics.barHeight` and the buttons are placed in its middle,
/// as far from the left edge as from the top (D-115).
/// AppKit lays the strip out again on a resize and on leaving full screen, so it is set after each.
@MainActor
final class WindowControls {
    private weak var window: NSWindow?
    /// Kept for the window's life (the app's one main window); the blocks hold `self` weakly.
    private var observers: [NSObjectProtocol] = []
    private var isFullScreen = false
    /// The system's distance between one button and the next, read once.
    private var pitch: CGFloat?

    init(window: NSWindow) {
        self.window = window
        let center = NotificationCenter.default
        let reapply: [NSNotification.Name] = [
            NSWindow.didResizeNotification, NSWindow.didEndLiveResizeNotification, NSWindow.didBecomeKeyNotification,
            NSWindow.didResignKeyNotification, NSWindow.didExitFullScreenNotification,
        ]
        for name in reapply {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if name == NSWindow.didExitFullScreenNotification {
                        self?.isFullScreen = false
                    }
                    self?.apply()
                }
            })
        }
        let entering = center
            .addObserver(forName: NSWindow.willEnterFullScreenNotification, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.isFullScreen = true }
            }
        observers.append(entering)
        apply()
    }

    /// Centres the buttons on the bar; in full screen the system's own title bar is left alone.
    func apply() {
        guard !isFullScreen, let window, let close = window.standardWindowButton(.closeButton),
              let strip = close.superview, let container = strip.superview
        else { return }
        let height = JGMetrics.barHeight
        var frame = container.frame
        if frame.height != height || frame.maxY != window.frame.height {
            frame.size.height = height
            frame.origin.y = window.frame.height - height
            container.frame = frame
        }
        if pitch == nil, let minimize = window.standardWindowButton(.miniaturizeButton) {
            pitch = minimize.frame.minX - close.frame.minX
        }
        // As far from the left edge as from the top (D-115).
        let margin = ((strip.bounds.height - close.frame.height) / 2).rounded()
        for (index, kind) in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton].enumerated() {
            guard let button = window.standardWindowButton(kind) else { continue }
            let origin = NSPoint(x: margin + CGFloat(index) * (pitch ?? 0), y: margin)
            if button.frame.origin != origin {
                button.setFrameOrigin(origin)
            }
        }
    }
}

/// Installs `WindowControls` on the window that hosts it.
struct WindowControlsInstaller: NSViewRepresentable {
    final class Probe: NSView {
        private var controls: WindowControls?

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, controls == nil else { return }
            controls = WindowControls(window: window)
            // After SwiftUI's first layout of the window.
            Task { @MainActor [weak self] in self?.controls?.apply() }
        }
    }

    func makeNSView(context _: Context) -> Probe {
        Probe()
    }

    func updateNSView(_: Probe, context _: Context) {}
}
