import AppKit
import CoreText
import JGDesign
import JGModel
import SwiftUI

/// The size map itself (D-127): the layout and the picture are made off the main thread into one image for the bounds;
/// hover and selection are two shape layers over it, so moving the pointer redraws nothing. A click selects the file in
/// the library, a double-click opens it, a double-click on a folder shows that folder.
///
/// A new tree is shown once its layout is ready: until then hover, clicks and the selection use the tree on screen
/// (`shown`), whose layout they index.
final class SizeMapCanvasView: NSView {
    var tree = SizeTree() {
        didSet {
            render()
        }
    }

    /// The library's selection, outlined in the accent.
    var selected: Set<Int64> = [] {
        didSet {
            if selected != oldValue {
                drawSelection()
            }
        }
    }

    var onHover: ((SizeTree.Node?) -> Void)?
    var onClick: ((SizeTree.Item) -> Void)?
    var onDoubleClick: ((SizeTree.Item) -> Void)?

    /// The tree on screen and its layout, always from the same render.
    private var shown = Shown()
    private var rendering: Task<Void, Never>?
    private var renderedSize = CGSize.zero
    private var hovered: Int?
    private let picture = CALayer()
    private let hoverLayer = CAShapeLayer()
    private let selectionLayer = CAShapeLayer()

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        picture.contentsGravity = .resize
        for shape in [hoverLayer, selectionLayer] {
            shape.fillColor = nil
            shape.actions = ["path": NSNull(), "hidden": NSNull()]
        }
        picture.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer?.addSublayer(picture)
        layer?.addSublayer(selectionLayer)
        layer?.addSublayer(hoverLayer)
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(String(localized: "Size Map", comment: "Section label of the size map; shown in capitals"))
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateLayer() {}

    override func layout() {
        super.layout()
        picture.frame = bounds
        hoverLayer.frame = bounds
        selectionLayer.frame = bounds
        if bounds.size != renderedSize {
            render()
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        render()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        render()
    }

    // MARK: Picture

    private func render() {
        rendering?.cancel()
        let size = bounds.size
        guard size.width > 0, size.height > 0 else { return }
        renderedSize = size
        let tree = tree
        let scale = window?.backingScaleFactor ?? 2
        let palette = Self.palette(for: effectiveAppearance)
        rendering = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> (Shown, CGImage?)? in
                let layout = SizeMapLayout(
                    tree, in: CGRect(origin: .zero, size: size), header: JGMetrics.sizeMapHeaderHeight,
                    padding: JGMetrics.sizeMapPadding, minSide: JGMetrics.sizeMapMinSide
                )
                guard !Task.isCancelled else { return nil }
                let image = SizeMapRenderer.image(tree, layout, size: size, scale: scale, palette: palette)
                return (Shown(tree: tree, layout: layout), image)
            }.value
            guard let self, !Task.isCancelled, let (next, image) = result else { return }
            setHovered(nil)
            shown = next
            picture.contents = image
            picture.contentsScale = scale
            drawSelection()
        }
    }

    private static func palette(for appearance: NSAppearance) -> SizeMapPalette {
        var palette = SizeMapPalette(
            isDark: true,
            folderFill: .init(red: 0, green: 0, blue: 0),
            headerFill: .init(red: 0, green: 0, blue: 0),
            label: .init(red: 1, green: 1, blue: 1),
            gap: .init(red: 0, green: 0, blue: 0)
        )
        appearance.performAsCurrentDrawingAppearance {
            func rgb(_ token: JGColorToken) -> SizeMapPalette.RGB {
                let color = token.nsColor.usingColorSpace(.sRGB) ?? .gray
                return .init(red: color.redComponent, green: color.greenComponent, blue: color.blueComponent)
            }
            palette = SizeMapPalette(
                isDark: appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua,
                folderFill: rgb(JGColor.bgPanel), headerFill: rgb(JGColor.bgRaised), label: rgb(JGColor.textSecondary),
                gap: rgb(JGColor.bgBase)
            )
        }
        return palette
    }

    // MARK: Hover and selection

    private func setHovered(_ node: Int?) {
        guard node != hovered else { return }
        hovered = node
        hoverLayer.path = node.flatMap { shown.layout.rects[$0] }.map { CGPath(rect: $0.insetBy(dx: 0.75, dy: 0.75), transform: nil) }
        effectiveAppearance.performAsCurrentDrawingAppearance {
            hoverLayer.strokeColor = JGColor.textPrimary.nsColor.cgColor
        }
        hoverLayer.lineWidth = JGMetrics.outlineWidth * 1.5
        onHover?(node.map { shown.tree.nodes[$0] })
    }

    private func drawSelection() {
        let path = CGMutablePath()
        for id in selected {
            if let node = shown.fileNodes[id], let rect = shown.layout.rects[node] {
                path.addRect(rect.insetBy(dx: 1, dy: 1))
            }
        }
        selectionLayer.path = path
        selectionLayer.lineWidth = JGMetrics.selectionEdgeWidth
        effectiveAppearance.performAsCurrentDrawingAppearance {
            selectionLayer.strokeColor = JGColor.accent.nsColor.cgColor
        }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: .zero, options: [.mouseMoved, .mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self
        ))
    }

    override func mouseMoved(with event: NSEvent) {
        setHovered(node(at: event))
    }

    override func mouseExited(with _: NSEvent) {
        setHovered(nil)
    }

    override func mouseDown(with event: NSEvent) {
        guard let node = node(at: event) else { return }
        let item = shown.tree.nodes[node].item
        if event.clickCount == 2 {
            onDoubleClick?(item)
        } else {
            onClick?(item)
        }
    }

    private func node(at event: NSEvent) -> Int? {
        shown.layout.hit(convert(event.locationInWindow, from: nil), in: shown.tree)
    }
}

/// A tree with its layout, and where each file's node is.
private struct Shown: Sendable {
    let tree: SizeTree
    let layout: SizeMapLayout
    let fileNodes: [Int64: Int]

    init(tree: SizeTree = SizeTree(), layout: SizeMapLayout = SizeMapLayout()) {
        self.tree = tree
        self.layout = layout
        fileNodes = Dictionary(tree.nodes.enumerated().compactMap { index, node in
            if case let .file(id) = node.item {
                (id, index)
            } else {
                nil
            }
        }, uniquingKeysWith: { first, _ in first })
    }
}

/// Draws a laid-out tree: the gaps in `bg.base`, folders in `bg.panel` with their name band in `bg.raised`, files in
/// their kind's family, names where they fit.
enum SizeMapRenderer {
    static func image(_ tree: SizeTree, _ layout: SizeMapLayout, size: CGSize, scale: CGFloat, palette: SizeMapPalette) -> CGImage? {
        guard let context = CGContext(
            data: nil, width: Int(size.width * scale), height: Int(size.height * scale), bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }
        // Flipped, as the view: y grows downward.
        context.translateBy(x: 0, y: size.height * scale)
        context.scaleBy(x: scale, y: -scale)
        context.textMatrix = CGAffineTransform(scaleX: 1, y: -1)
        context.setFillColor(palette.gap.cgColor)
        context.fill(CGRect(origin: .zero, size: size))
        let font = CTFontCreateUIFontForLanguage(.system, JGTextStyle.mono.size, nil)
            ?? CTFontCreateWithName("Helvetica" as CFString, JGTextStyle.mono.size, nil)
        let sizes = ByteCountFormatter()
        sizes.countStyle = .file
        let fileInk = palette.isDark ? CGColor(gray: 1, alpha: 0.88) : CGColor(gray: 0, alpha: 0.72)
        for box in layout.boxes {
            let node = tree.nodes[box.node]
            let rect = box.rect.width > 2 && box.rect.height > 2 ? box.rect.insetBy(dx: 0.5, dy: 0.5) : box.rect
            if let kind = node.kind {
                context.setFillColor(palette.color(kind: kind, fileExtension: node.fileExtension).cgColor)
                context.fill(rect)
                if rect.width >= 64, rect.height >= JGMetrics.sizeMapHeaderHeight {
                    draw(node.name, in: rect.insetBy(dx: 4, dy: 2), style: Label(font: font, color: fileInk, top: true), context: context)
                }
            } else {
                context.setFillColor(palette.folderFill.cgColor)
                context.fill(rect)
                if let header = box.header {
                    context.setFillColor(palette.headerFill.cgColor)
                    context.fill(header.insetBy(dx: 0.5, dy: 0.5))
                    let text = node.name + "  " + sizes.string(fromByteCount: node.size)
                    draw(
                        text,
                        in: header.insetBy(dx: 4, dy: 0),
                        style: Label(font: font, color: palette.label.cgColor, top: false),
                        context: context
                    )
                }
            }
        }
        return context.makeImage()
    }

    /// One line of `text`, truncated in the middle to `rect`'s width, centred in its height (or at its top).
    /// How a name is drawn: its font and color, at the top of its rectangle or centred in it.
    private struct Label {
        let font: CTFont
        let color: CGColor
        let top: Bool
    }

    private static func draw(_ text: String, in rect: CGRect, style: Label, context: CGContext) {
        let font = style.font
        let color = style.color
        let top = style.top
        let attributes: [NSAttributedString.Key: Any] = [
            .init(kCTFontAttributeName as String): font,
            .init(kCTForegroundColorAttributeName as String): color,
        ]
        let line = CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: attributes))
        let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
        guard rect.width > 8, let fitted = CTLineCreateTruncatedLine(line, Double(rect.width), .middle, ellipsis) else { return }
        var ascent: CGFloat = 0
        var descent: CGFloat = 0
        _ = CTLineGetTypographicBounds(fitted, &ascent, &descent, nil)
        let baseline = top ? rect.minY + ascent + 2 : rect.midY + (ascent - descent) / 2
        context.textPosition = CGPoint(x: rect.minX, y: baseline)
        CTLineDraw(fitted, context)
    }
}

/// SwiftUI host of the size map.
struct SizeMapCanvas: NSViewRepresentable {
    let tree: SizeTree
    /// Changes with every new tree (comparing trees of many files on each update would cost).
    let treeVersion: Int
    let selected: Set<Int64>
    let onHover: (SizeTree.Node?) -> Void
    let onClick: (SizeTree.Item) -> Void
    let onDoubleClick: (SizeTree.Item) -> Void

    final class Coordinator {
        var treeVersion = -1
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context _: Context) -> SizeMapCanvasView {
        SizeMapCanvasView(frame: .zero)
    }

    func updateNSView(_ view: SizeMapCanvasView, context: Context) {
        view.onHover = onHover
        view.onClick = onClick
        view.onDoubleClick = onDoubleClick
        if context.coordinator.treeVersion != treeVersion {
            context.coordinator.treeVersion = treeVersion
            view.tree = tree
        }
        view.selected = selected
    }
}
