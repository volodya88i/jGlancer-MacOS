import AppKit
import JGDesign
import SwiftUI

/// Zoom commands of the photo view (⌘0 fit, ⌘9 fill, ⌘1 actual size, ⌘+ / ⌘−).
enum ZoomCommand: Equatable {
    case fit, fill, actualSize, zoomIn, zoomOut
}

/// The photo canvas: an `NSScrollView` with magnification (pinch, ⌘ keys, mouse wheel, double-click) that centers
/// the image, pans when zoomed, and at fit hands two-finger swipes and mouse drags to the swipe pager; horizontal
/// wheel ticks turn pages (docs/FEATURES.md §4.1).
final class PhotoScrollView: NSScrollView {
    var onNavigate: ((Int) -> Void)?
    var onSwipe: ((SwipeInput) -> Void)?
    var onClose: (() -> Void)?
    var onZoomedBeyondFit: (() -> Void)?
    var onActivity: (() -> Void)?
    var onContextMenu: (() -> NSMenu?)?

    private let imageView = PhotoImageView()
    /// The animation of a GIF or animated PNG, drawn straight into `imageView` (no SwiftUI work per frame).
    private let animation = AnimatedImagePlayer()
    /// The still image last given by `display`, so a SwiftUI update does not put it back over a running animation.
    private var still: CGImage?
    private var fullSize = CGSize.zero
    /// True while the image follows the window size at fit; false once the user zooms.
    private var isFitted = true
    /// A mouse drag at fit is a swipe.
    private var isDragging = false
    /// Zoom factor of ⌘+ / ⌘− and of one mouse-wheel tick.
    private static let keyZoomStep: CGFloat = 1.25
    private static let wheelZoomStep: CGFloat = 1.1

    override init(frame: NSRect) {
        super.init(frame: frame)
        contentView = CenteringClipView()
        documentView = imageView
        hasVerticalScroller = false
        hasHorizontalScroller = false
        drawsBackground = false
        allowsMagnification = true
        usesPredominantAxisScrolling = false
        NotificationCenter.default.addObserver(
            self, selector: #selector(liveMagnifyEnded), name: NSScrollView.didEndLiveMagnifyNotification, object: self
        )
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
        if window == nil {
            animation.stop()
        }
    }

    // MARK: Content

    /// Shows `image` for a photo of `fullSize` pixels. A new photo resets to fit; a refined image of the same
    /// photo keeps the zoom.
    func display(_ image: CGImage?, fullSize newSize: CGSize, isNewPhoto: Bool) {
        if image !== still || isNewPhoto {
            still = image
            imageView.image = image
        }
        guard newSize.width > 0, newSize.height > 0 else { return }
        if isNewPhoto || newSize != fullSize {
            fullSize = newSize
            let scale = window?.backingScaleFactor ?? 2
            // 100 % = one image pixel per device pixel.
            imageView.frame = CGRect(origin: .zero, size: CGSize(width: newSize.width / scale, height: newSize.height / scale))
            zoomToFit()
        }
    }

    /// Plays the animated picture at `url` in place of the still one, or stops (nil: another photo, turned, or none).
    func animate(_ url: URL?) {
        guard let url, window != nil else {
            if animation.url != nil {
                animation.stop()
                imageView.image = still
            }
            return
        }
        animation.play(url) { [weak self] frame in
            self?.imageView.image = frame
        }
    }

    // MARK: Zoom

    var fitMagnification: CGFloat {
        let viewport = contentView.bounds.size.applying(CGAffineTransform(scaleX: magnification, y: magnification))
        let document = imageView.frame.size
        guard document.width > 0, document.height > 0 else { return 1 }
        // Fit never enlarges small photos beyond actual size.
        return min(1, viewport.width / document.width, viewport.height / document.height)
    }

    private var fillMagnification: CGFloat {
        let viewport = contentView.bounds.size.applying(CGAffineTransform(scaleX: magnification, y: magnification))
        let document = imageView.frame.size
        guard document.width > 0, document.height > 0 else { return 1 }
        return max(viewport.width / document.width, viewport.height / document.height)
    }

    func zoom(_ command: ZoomCommand) {
        switch command {
        case .fit: zoomToFit()
        case .fill: setZoom(fillMagnification, centeredAt: nil)
        case .actualSize: setZoom(1, centeredAt: nil)
        case .zoomIn: setZoom(magnification * Self.keyZoomStep, centeredAt: nil)
        case .zoomOut: setZoom(magnification / Self.keyZoomStep, centeredAt: nil)
        }
    }

    private func zoomToFit() {
        let fit = fitMagnification
        minMagnification = fit / 2
        maxMagnification = max(8, fit)
        magnification = fit
        isFitted = true
    }

    private func setZoom(_ value: CGFloat, centeredAt point: CGPoint?) {
        let clamped = min(max(value, minMagnification), maxMagnification)
        if let point {
            setMagnification(clamped, centeredAt: point)
        } else {
            let center = CGPoint(x: contentView.bounds.midX, y: contentView.bounds.midY)
            setMagnification(clamped, centeredAt: center)
        }
        zoomChanged()
    }

    private func zoomChanged() {
        isFitted = abs(magnification - fitMagnification) < 0.001
        if magnification > fitMagnification * 1.01 {
            onZoomedBeyondFit?()
        }
    }

    @objc private func liveMagnifyEnded() {
        zoomChanged()
    }

    override func layout() {
        super.layout()
        if isFitted {
            zoomToFit()
        }
    }

    // MARK: Input

    override func mouseDown(with event: NSEvent) {
        onActivity?()
        isDragging = false
        guard event.clickCount == 2 else {
            super.mouseDown(with: event)
            return
        }
        let point = imageView.convert(event.locationInWindow, from: nil)
        if isFitted {
            setZoom(1, centeredAt: point)
        } else {
            zoomToFit()
        }
    }

    override func mouseDragged(with event: NSEvent) {
        guard isFitted else {
            super.mouseDragged(with: event)
            return
        }
        if !isDragging {
            isDragging = true
            onSwipe?(.began)
        }
        onSwipe?(.moved(delta: event.deltaX, time: event.timestamp))
    }

    override func mouseUp(with event: NSEvent) {
        if isDragging {
            isDragging = false
            onSwipe?(.ended)
        } else {
            super.mouseUp(with: event)
        }
    }

    override func scrollWheel(with event: NSEvent) {
        onActivity?()
        if event.hasPreciseScrollingDeltas {
            if isFitted, abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) || [.ended, .cancelled].contains(event.phase) {
                swipe(event)
            } else if !isFitted {
                super.scrollWheel(with: event)
            }
            return
        }
        // Mouse wheel: horizontal ticks turn pages, vertical ticks zoom around the pointer.
        if abs(event.scrollingDeltaX) > abs(event.scrollingDeltaY) {
            onNavigate?(event.scrollingDeltaX > 0 ? -1 : 1)
        } else if event.scrollingDeltaY != 0 {
            let point = imageView.convert(event.locationInWindow, from: nil)
            setZoom(magnification * (event.scrollingDeltaY > 0 ? Self.wheelZoomStep : 1 / Self.wheelZoomStep), centeredAt: point)
        }
    }

    /// Two-finger swipes go to the pager (fingers left shows the next photo, whatever the natural-scrolling
    /// setting); the momentum after the fingers lift is ignored.
    private func swipe(_ event: NSEvent) {
        guard event.momentumPhase.isEmpty else { return }
        switch event.phase {
        case .began:
            onSwipe?(.began)
            onSwipe?(.moved(delta: SwipeInput.contentDelta(of: event), time: event.timestamp))
        case .changed:
            onSwipe?(.moved(delta: SwipeInput.contentDelta(of: event), time: event.timestamp))
        case .ended, .cancelled:
            onSwipe?(.ended)
        default:
            break
        }
    }

    override func keyDown(with event: NSEvent) {
        onActivity?()
        interpretKeyEvents([event])
    }

    override func menu(for _: NSEvent) -> NSMenu? {
        onContextMenu?()
    }

    override func moveLeft(_: Any?) {
        onNavigate?(-1)
    }

    override func moveRight(_: Any?) {
        onNavigate?(1)
    }

    override func cancelOperation(_: Any?) {
        onClose?()
    }

    override func insertText(_: Any) {}

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let key = event.charactersIgnoringModifiers
        else { return super.performKeyEquivalent(with: event) }
        let command: ZoomCommand? = switch key {
        case "0": .fit
        case "9": .fill
        case "1": .actualSize
        case "=", "+": .zoomIn
        case "-": .zoomOut
        default: nil
        }
        guard let command else { return super.performKeyEquivalent(with: event) }
        onActivity?()
        zoom(command)
        return true
    }
}

/// Centers the document when it is smaller than the viewport.
final class CenteringClipView: NSClipView {
    override func constrainBoundsRect(_ proposedBounds: NSRect) -> NSRect {
        var rect = super.constrainBoundsRect(proposedBounds)
        guard let document = documentView?.frame else { return rect }
        if rect.width > document.width {
            rect.origin.x = (document.width - rect.width) / 2
        }
        if rect.height > document.height {
            rect.origin.y = (document.height - rect.height) / 2
        }
        return rect
    }
}

/// The image itself: layer contents only, scaled by Core Animation (no backing store, no main-thread decode).
final class PhotoImageView: NSView {
    var image: CGImage? {
        didSet { layer?.contents = image }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        layer?.contentsGravity = .resize
        layer?.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateLayer() {}
}

/// SwiftUI host of the photo canvas.
struct PhotoCanvas: NSViewRepresentable {
    let model: PhotoViewerModel
    let picture: PhotoViewerModel.Picture?
    let index: Int
    let zoomCommand: (command: ZoomCommand, serial: Int)?
    let pager: SwipePager
    let onClose: () -> Void
    let onActivity: () -> Void
    var contextMenu: () -> NSMenu? = { nil }

    final class Coordinator {
        var index = -1
        var zoomSerial = 0
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context _: Context) -> PhotoScrollView {
        let view = PhotoScrollView(frame: .zero)
        view.onNavigate = { [model] offset in model.move(by: offset) }
        view.onZoomedBeyondFit = { [model] in model.requestFullResolution() }
        view.onSwipe = { [pager] input in pager.handle(input) }
        return view
    }

    func updateNSView(_ view: PhotoScrollView, context: Context) {
        view.onClose = onClose
        view.onContextMenu = contextMenu
        view.onActivity = onActivity
        view.setAccessibilityLabel(model.currentPhoto?.name)
        let isNewPhoto = context.coordinator.index != index
        context.coordinator.index = index
        view.display(picture?.image, fullSize: picture?.fullSize ?? .zero, isNewPhoto: isNewPhoto)
        view.animate(model.animatedURL)
        if let zoomCommand, zoomCommand.serial != context.coordinator.zoomSerial {
            context.coordinator.zoomSerial = zoomCommand.serial
            view.zoom(zoomCommand.command)
        }
    }
}
