import AppKit
import JGModel
import SwiftUI

/// One side of Compare: the photo in a layer placed by its `CompareZoom`. Drags and trackpad scrolls pan, the mouse
/// wheel and pinches zoom around the pointer, a double-click goes between fit and 100 %, ⌘0 / ⌘1 / ⌘+ / ⌘− zoom the
/// focused side, L links or unlinks, X swaps (W-77). The zoom itself lives in `CompareModel`.
final class CompareCanvasView: NSView {
    /// Runs a zoom change with the picture's size at 100 % and the view's bounds (the model owns the zoom).
    var onZoom: (((inout CompareZoom, CGSize, CGRect) -> Void) -> Void)?
    var onKey: ((CompareModel.Key) -> Void)?
    /// The view's bounds and backing scale, for zoom keys and buttons applied by the model.
    var onLayout: ((CGRect, CGFloat) -> Void)?
    var onFocus: (() -> Void)?
    var onContextMenu: (() -> NSMenu?)?
    var takesFocusFirst = false

    private let imageLayer = CALayer()
    private var image: CGImage?
    private var pixelSize = CGSize.zero
    private var zoom = CompareZoom()
    private var lastDrag: CGPoint?
    private static let wheelStep: CGFloat = 1.1

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.masksToBounds = true
        imageLayer.contentsGravity = .resize
        imageLayer.magnificationFilter = .nearest
        layer?.addSublayer(imageLayer)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    /// The photo's size in points at 100 % (one image pixel per device pixel).
    private var actualSize: CGSize {
        let scale = window?.backingScaleFactor ?? 2
        return CGSize(width: pixelSize.width / scale, height: pixelSize.height / scale)
    }

    func show(_ image: CGImage?, pixelSize: CGSize, zoom: CompareZoom) {
        self.image = image
        self.pixelSize = pixelSize
        self.zoom = zoom
        place()
    }

    private func place() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        imageLayer.contents = image
        imageLayer.frame = image == nil ? .zero : zoom.frame(of: actualSize, in: bounds)
        imageLayer.contentsScale = window?.backingScaleFactor ?? 2
        CATransaction.commit()
    }

    override func layout() {
        super.layout()
        onLayout?(bounds, window?.backingScaleFactor ?? 2)
        place()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        onLayout?(bounds, window?.backingScaleFactor ?? 2)
        place()
    }

    // MARK: Input

    override var acceptsFirstResponder: Bool {
        true
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if takesFocusFirst {
            window?.makeFirstResponder(self)
        }
    }

    private func change(_ body: (inout CompareZoom, CGSize, CGRect) -> Void) {
        onZoom?(body)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        onFocus?()
        let point = convert(event.locationInWindow, from: nil)
        lastDrag = point
        guard event.clickCount == 2 else { return }
        let isFit = zoom.isFit
        change { zoom, size, bounds in
            if isFit {
                zoom.zoom(to: CompareZoom.actualScale(of: size, in: bounds.size), at: point, actualSize: size, in: bounds)
            } else {
                zoom.reset()
            }
        }
    }

    override func mouseDragged(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        let delta = CGVector(dx: point.x - (lastDrag?.x ?? point.x), dy: point.y - (lastDrag?.y ?? point.y))
        lastDrag = point
        change { zoom, size, bounds in zoom.pan(by: delta, actualSize: size, in: bounds) }
    }

    override func mouseUp(with _: NSEvent) {
        lastDrag = nil
    }

    override func scrollWheel(with event: NSEvent) {
        onFocus?()
        if event.hasPreciseScrollingDeltas {
            let delta = CGVector(dx: event.scrollingDeltaX, dy: -event.scrollingDeltaY)
            change { zoom, size, bounds in zoom.pan(by: delta, actualSize: size, in: bounds) }
        } else if event.scrollingDeltaY != 0 {
            let point = convert(event.locationInWindow, from: nil)
            let factor = event.scrollingDeltaY > 0 ? Self.wheelStep : 1 / Self.wheelStep
            change { zoom, size, bounds in zoom.zoom(by: factor, at: point, actualSize: size, in: bounds) }
        }
    }

    override func magnify(with event: NSEvent) {
        onFocus?()
        let point = convert(event.locationInWindow, from: nil)
        let factor = 1 + event.magnification
        change { zoom, size, bounds in zoom.zoom(by: factor, at: point, actualSize: size, in: bounds) }
    }

    override func keyDown(with event: NSEvent) {
        guard event.modifierFlags.isDisjoint(with: .deviceIndependentFlagsMask) else {
            super.keyDown(with: event)
            return
        }
        switch event.charactersIgnoringModifiers?.lowercased() {
        case "l": onKey?(.toggleLink)
        case "x": onKey?(.swap)
        default: super.keyDown(with: event)
        }
    }

    /// ⌘0, ⌘1, ⌘+ and ⌘− reach every view; the first canvas takes them for the focused side.
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command,
              let key = event.charactersIgnoringModifiers
        else { return super.performKeyEquivalent(with: event) }
        let command: CompareModel.Key? = switch key {
        case "0": .fit
        case "1": .actualSize
        case "=", "+": .zoomIn
        case "-": .zoomOut
        default: nil
        }
        guard let command else { return super.performKeyEquivalent(with: event) }
        onKey?(command)
        return true
    }

    override func menu(for _: NSEvent) -> NSMenu? {
        onFocus?()
        return onContextMenu?()
    }
}

/// A side of Compare in SwiftUI.
struct CompareCanvas: NSViewRepresentable {
    let model: CompareModel
    let side: Int
    let contextMenu: (Int) -> NSMenu?

    func makeNSView(context _: Context) -> CompareCanvasView {
        let view = CompareCanvasView()
        view.takesFocusFirst = side == 0
        return view
    }

    func updateNSView(_ view: CompareCanvasView, context _: Context) {
        let model = model
        let side = side
        view.onZoom = { change in model.changeZoom(of: side, change) }
        view.onLayout = { bounds, scale in model.setLayout(of: side, bounds: bounds, backingScale: scale) }
        view.onFocus = { model.focusedSide = side }
        view.onKey = { key in model.apply(key) }
        view.onContextMenu = { contextMenu(side) }
        let shown = model.sides[side]
        view.show(shown.image, pixelSize: shown.pixelSize, zoom: model.zoom(of: side))
    }
}
