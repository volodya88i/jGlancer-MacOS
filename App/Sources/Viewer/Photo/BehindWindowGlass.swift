import AppKit
import JGDesign
import SwiftUI

/// What lies behind the window (the desktop, other apps), blurred, under the media color at
/// `JGMetrics.behindWindowTintOpacity`: the see-through photo viewer's background (D-114).
struct BehindWindowGlass: NSViewRepresentable {
    func makeNSView(context _: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.blendingMode = .behindWindow
        view.material = .fullScreenUI
        view.state = .active
        view.alphaValue = JGMetrics.behindWindowBlurOpacity
        return view
    }

    func updateNSView(_: NSVisualEffectView, context _: Context) {}
}

/// Makes the hosting window see-through while `isOn` (its own background clear), and opaque again after (D-114).
struct WindowSeeThrough: NSViewRepresentable {
    let isOn: Bool

    final class Probe: NSView {
        var isOn = false {
            didSet { apply() }
        }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            apply()
        }

        func apply() {
            guard let window else { return }
            window.isOpaque = !isOn
            window.backgroundColor = isOn ? .clear : .windowBackgroundColor
        }
    }

    func makeNSView(context _: Context) -> Probe {
        Probe()
    }

    func updateNSView(_ view: Probe, context _: Context) {
        if view.isOn != isOn {
            view.isOn = isOn
        }
    }
}
