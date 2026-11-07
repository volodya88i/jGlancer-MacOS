import AppKit
import SwiftUI

/// A picture that plays its animation (a GIF or animated PNG, D-124), aspect-fit like a resizable `Image`: the still
/// shows until the first frame; frames go straight into a layer, so SwiftUI does no work per frame. The animation
/// stops when the view leaves its window.
struct AnimatedPicture: NSViewRepresentable {
    let url: URL
    let still: CGImage

    func makeNSView(context _: Context) -> AnimatedPictureView {
        AnimatedPictureView()
    }

    func updateNSView(_ view: AnimatedPictureView, context _: Context) {
        view.show(still, animating: url)
    }
}

/// The layer `AnimatedPicture` plays into.
final class AnimatedPictureView: NSView {
    private let player = AnimatedImagePlayer()
    private var url: URL?

    init() {
        super.init(frame: .zero)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.contentsGravity = .resizeAspect
        layer?.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateLayer() {}

    func show(_ still: CGImage, animating newURL: URL) {
        guard newURL != url else { return }
        url = newURL
        layer?.contents = still
        play()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil {
            player.stop()
        } else {
            play()
        }
    }

    private func play() {
        guard let url, window != nil else { return }
        player.play(url) { [weak self] frame in
            self?.layer?.contents = frame
        }
    }
}
