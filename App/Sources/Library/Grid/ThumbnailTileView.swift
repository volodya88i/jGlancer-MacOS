import AppKit
import JGDesign
import JGModel

/// One grid tile drawn with layers (no SwiftUI view per item; docs/ARCHITECTURE.md §7):
/// aspect-fit thumbnail with small radius, kind glyph when there is no thumbnail, duration badge,
/// flag star in the top-right corner, optional name, hover and selection states (docs/DESIGN.md §8).
final class ThumbnailTileView: NSView {
    struct Content: Equatable {
        var name: String?
        var kind: MediaKind
        var duration: String?
        var showsCaption: Bool
        var accessibilityKind: String
        var flag = AssetFlag.none
        /// The head of an image sequence: its frame count, and whether it is unfolded (D-84).
        var sequenceFrames: Int?
        var sequenceUnfolded = false
        /// Kept only in the cloud (D-124): a cloud instead of the kind glyph while there is no thumbnail.
        var isCloudOnly = false
    }

    var content = Content(name: nil, kind: .photo, duration: nil, showsCaption: false, accessibilityKind: "") {
        didSet {
            if content != oldValue {
                needsLayout = true; updateTextAndGlyph()
            }
        }
    }

    /// The thumbnail; nil shows a glyph tile once `isLoading` is false.
    var image: CGImage? {
        didSet {
            if image !== oldValue {
                imageLayer.contents = image; needsLayout = true; updateTextAndGlyph()
            }
        }
    }

    var isLoading = true {
        didSet {
            if isLoading != oldValue {
                updateTextAndGlyph(); updateColors()
            }
        }
    }

    var isSelected = false {
        didSet {
            if isSelected != oldValue {
                updateColors(); setAccessibilitySelected(isSelected)
            }
        }
    }

    /// Decor (Settings): "+" marks at the corners of a selected tile (docs/DESIGN.md §6).
    var showsCrosshairs = false {
        didSet {
            if showsCrosshairs != oldValue {
                updateColors()
            }
        }
    }

    private var isHovered = false {
        didSet {
            if isHovered != oldValue {
                updateColors()
                fadeHover()
            }
        }
    }

    /// No implicit animations on the tile's layers: a selection follows the keyboard at once, and a tile reused while
    /// scrolling never fades its selection or placeholder in (Core Animation's default is a 0.25 s fade on every
    /// color change). Only hover fades, explicitly (`fadeHover`).
    static let quietActions: [String: any CAAction] = [
        "contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "hidden": NSNull(), "backgroundColor": NSNull(),
        "borderColor": NSNull(), "borderWidth": NSNull(), "foregroundColor": NSNull(), "strokeColor": NSNull(),
    ]

    /// The hover outline and wash fade in and out (docs/DESIGN.md §9) from what is drawn now.
    private func fadeHover() {
        for (layer, keyPath) in [(backgroundLayer, "backgroundColor"), (borderLayer, "borderColor"), (borderLayer, "borderWidth")] {
            let fade = CABasicAnimation(keyPath: keyPath)
            fade.duration = JGMetrics.fadeDuration
            fade.timingFunction = CAMediaTimingFunction(name: .easeOut)
            layer.add(fade, forKey: keyPath)
        }
    }

    private let backgroundLayer = CALayer()
    let imageLayer = CALayer()
    private let glyphLayer = CALayer()
    private let borderLayer = CALayer()
    private let badgeLayer = CATextLayer()
    private let captionLayer = CATextLayer()
    private let crosshairLayer = CAShapeLayer()
    /// The flag: a star on a dense badge, so every color reads over any thumbnail (`JGMetrics.flagBadgeOpacity`).
    private let flagLayer = CALayer()
    /// A folded sequence: two cards turned ±3° behind its first frame, and the badge with its frame count.
    let stackLayers = [CALayer(), CALayer()]
    let sequenceBadge = CALayer()
    let sequenceGlyph = CALayer()
    let sequenceCount = CATextLayer()
    /// › while folded, ‹ while unfolded (W-86).
    let sequenceArrow = CALayer()
    private var trackingArea: NSTrackingArea?

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layerContentsRedrawPolicy = .never
        for layer in [backgroundLayer, imageLayer, glyphLayer, borderLayer] {
            layer.cornerRadius = JGMetrics.radiusSmall
            layer.cornerCurve = .continuous
        }
        imageLayer.masksToBounds = true
        imageLayer.contentsGravity = .resize
        glyphLayer.contentsGravity = .center
        badgeLayer.font = NSFont.monospacedDigitSystemFont(ofSize: JGTextStyle.mono.size, weight: .medium)
        badgeLayer.fontSize = JGTextStyle.mono.size
        badgeLayer.alignmentMode = .center
        badgeLayer.cornerRadius = JGMetrics.radiusSmall / 2
        captionLayer.font = NSFont.systemFont(ofSize: JGTextStyle.body.size)
        captionLayer.fontSize = JGTextStyle.body.size
        captionLayer.truncationMode = .middle
        captionLayer.alignmentMode = .center
        flagLayer.cornerRadius = JGMetrics.radiusSmall / 2
        flagLayer.contentsGravity = .center
        crosshairLayer.lineWidth = JGMetrics.outlineWidth
        crosshairLayer.fillColor = nil
        for layer in stackLayers + [
            backgroundLayer,
            imageLayer,
            glyphLayer,
            borderLayer,
            badgeLayer,
            flagLayer,
            captionLayer,
            crosshairLayer,
        ] {
            layer.actions = ThumbnailTileView.quietActions
            self.layer?.addSublayer(layer)
        }
        setUpSequenceLayers()
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        updateColors()
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override var isFlipped: Bool {
        true
    }

    /// Layers only: without this AppKit gives every tile a full-size bitmap backing store it never draws into.
    override var wantsUpdateLayer: Bool {
        true
    }

    override func updateLayer() {}

    override func layout() {
        super.layout()
        let scale = window?.backingScaleFactor ?? 2
        for layer in [badgeLayer, captionLayer, glyphLayer, flagLayer] {
            layer.contentsScale = scale
        }
        let side = bounds.width
        let square = CGRect(x: 0, y: 0, width: side, height: side)
        backgroundLayer.frame = square
        borderLayer.frame = square
        glyphLayer.frame = square
        imageLayer.frame = image.map { Self.aspectFit(CGSize(width: $0.width, height: $0.height), in: square) } ?? square
        layoutSequence(in: square)
        // The duration sits at the bottom right (D-105): the top left is often where a picture's subject is.
        let badgeSize = badgeLayer.preferredFrameSize()
        let inset = JGMetrics.badgeInset
        let badgeHeight = badgeSize.height + JGMetrics.badgeExtraHeight
        badgeLayer.frame = CGRect(
            x: imageLayer.frame.maxX - inset - badgeSize.width - 2 * inset, y: imageLayer.frame.maxY - inset - badgeHeight,
            width: badgeSize.width + 2 * inset, height: badgeHeight
        )
        let flagSide = JGMetrics.flagBadgeSide
        flagLayer.frame = CGRect(
            x: imageLayer.frame.maxX - inset - flagSide, y: imageLayer.frame.minY + inset, width: flagSide, height: flagSide
        )
        crosshairLayer.frame = square
        crosshairLayer.path = Self.crosshairs(around: square)
        captionLayer.isHidden = !content.showsCaption
        captionLayer.frame = CGRect(x: 0, y: side + inset, width: side, height: bounds.height - side - inset)
    }

    // MARK: Appearance

    /// Another screen (1× or 2×): the glyph is drawn again for it.
    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        updateTextAndGlyph()
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
        updateTextAndGlyph()
    }

    private func updateColors() {
        updateSequenceColors()
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let showsPlaceholder = image == nil
            backgroundLayer.backgroundColor = if isSelected {
                JGColor.accentDim.nsColor.cgColor
            } else if isHovered || showsPlaceholder {
                JGColor.bgRaised.nsColor.cgColor
            } else {
                NSColor.clear.cgColor
            }
            borderLayer.borderWidth = isSelected ? JGMetrics.selectionEdgeWidth : (isHovered ? JGMetrics.outlineWidth : 0)
            borderLayer.borderColor = (isSelected ? JGColor.accent : JGColor.lineStrong).nsColor.cgColor
            badgeLayer.backgroundColor = JGColor.overlayScrim.nsColor.cgColor
            badgeLayer.foregroundColor = JGColor.textPrimary.nsColor.cgColor
            flagLayer.backgroundColor = JGColor.bgBase.nsColor.withAlphaComponent(JGMetrics.flagBadgeOpacity).cgColor
            captionLayer.foregroundColor = (isSelected ? JGColor.textPrimary : JGColor.textSecondary).nsColor.cgColor
            crosshairLayer.strokeColor = JGColor.accent.nsColor.cgColor
            crosshairLayer.isHidden = !(isSelected && showsCrosshairs)
        }
    }

    private func updateTextAndGlyph() {
        badgeLayer.string = content.duration
        badgeLayer.isHidden = content.duration == nil
        captionLayer.string = content.name
        flagLayer.isHidden = content.flag == .none
        if content.flag != .none {
            flagLayer.contents = content.flag.starImage(pointSize: JGMetrics.flagStarSize, appearance: effectiveAppearance)
        }
        let showsGlyph = image == nil && !isLoading
        glyphLayer.isHidden = !showsGlyph
        if showsGlyph {
            glyphLayer.contents = Self.glyph(
                for: content.kind, isCloudOnly: content.isCloudOnly, appearance: effectiveAppearance,
                scale: window?.backingScaleFactor ?? 2
            )
        }
        let flagName = content.flag == .none ? nil : content.flag.title
        updateSequenceText()
        let frames = content.sequenceFrames.map {
            String(localized: "image sequence, \($0) frames", comment: "Grid tile accessibility: a folded image sequence")
        }
        let cloud = content.isCloudOnly
            ? String(localized: "in the cloud", comment: "Grid tile accessibility: the file is kept only in iCloud or another cloud")
            : nil
        setAccessibilityLabel([content.name, content.accessibilityKind, frames, content.duration, flagName, cloud]
            .compactMap(\.self).joined(separator: ", "))
        updateColors()
        needsLayout = true
    }

    // MARK: Hover

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea {
            removeTrackingArea(trackingArea)
        }
        let area = NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self)
        addTrackingArea(area)
        trackingArea = area
    }

    override func mouseEntered(with _: NSEvent) {
        isHovered = true
    }

    override func mouseExited(with _: NSEvent) {
        isHovered = false
    }

    func resetForReuse() {
        image = nil
        isLoading = true
        isSelected = false
        isHovered = false
        // A tile going back to the pool shows nothing of the last one's hover.
        backgroundLayer.removeAllAnimations()
        borderLayer.removeAllAnimations()
    }
}

/// Collection-view item hosting a `ThumbnailTileView`.
final class ThumbnailItem: NSCollectionViewItem {
    static let identifier = NSUserInterfaceItemIdentifier("ThumbnailItem")

    var tile: ThumbnailTileView? {
        view as? ThumbnailTileView
    }

    /// Asset shown by this item (to match late thumbnail results).
    var assetID: Int64?

    override func loadView() {
        view = ThumbnailTileView(frame: .zero)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        assetID = nil
        tile?.resetForReuse()
        // Glides belong to the tile shown before.
        view.layer?.removeAllAnimations()
    }
}
