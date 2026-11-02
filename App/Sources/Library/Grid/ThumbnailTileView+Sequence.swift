import AppKit
import JGDesign

/// The look of an image sequence's head tile (D-84, W-81): folded, its first frame shrunk a little over two cards
/// turned ±3°, and a badge at the bottom right with a stack glyph and the frame count; unfolded, the badge only, in
/// the accent colour. The badge ends with an arrow: › folded (a click unfolds), ‹ unfolded (a click folds; W-86). The
/// badge is a button (`sequenceBadgeFrame`).
extension ThumbnailTileView {
    static let stackTurn: CGFloat = 3 * .pi / 180
    /// The folded first frame's share of the tile.
    static let foldedScale: CGFloat = 0.88

    var isFoldedSequence: Bool {
        content.sequenceFrames != nil && !content.sequenceUnfolded
    }

    /// Where a click toggles the sequence, in the tile's coordinates; nil for other tiles.
    var sequenceBadgeFrame: CGRect? {
        content.sequenceFrames == nil ? nil : sequenceBadge.frame.insetBy(dx: -JGMetrics.badgeInset, dy: -JGMetrics.badgeInset)
    }

    func setUpSequenceLayers() {
        for card in stackLayers {
            card.cornerRadius = JGMetrics.radiusSmall
            card.cornerCurve = .continuous
            card.borderWidth = JGMetrics.outlineWidth
            card.isHidden = true
        }
        sequenceBadge.cornerRadius = JGMetrics.radiusSmall / 2
        sequenceBadge.isHidden = true
        sequenceGlyph.contentsGravity = .center
        sequenceArrow.contentsGravity = .center
        sequenceCount.font = NSFont.monospacedDigitSystemFont(ofSize: JGTextStyle.mono.size, weight: .medium)
        sequenceCount.fontSize = JGTextStyle.mono.size
        sequenceCount.alignmentMode = .left
        for layer in [sequenceBadge, sequenceGlyph, sequenceCount, sequenceArrow] {
            layer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull(), "hidden": NSNull()]
        }
        sequenceBadge.addSublayer(sequenceGlyph)
        sequenceBadge.addSublayer(sequenceCount)
        sequenceBadge.addSublayer(sequenceArrow)
        layer?.addSublayer(sequenceBadge)
    }

    func layoutSequence(in square: CGRect) {
        let folded = isFoldedSequence
        for (index, card) in stackLayers.enumerated() {
            card.isHidden = !folded
            guard folded else { continue }
            let fitted = image.map { Self.aspectFit(CGSize(width: $0.width, height: $0.height), in: square) } ?? square
            let shrink = (1 - Self.foldedScale) / 2
            let shrunk = fitted.insetBy(dx: fitted.width * shrink, dy: fitted.height * shrink)
            card.bounds = CGRect(origin: .zero, size: shrunk.size)
            card.position = CGPoint(x: shrunk.midX, y: shrunk.midY)
            card.setAffineTransform(CGAffineTransform(rotationAngle: index == 0 ? -Self.stackTurn : Self.stackTurn))
        }
        if folded {
            let fitted = imageLayer.frame
            let shrink = (1 - Self.foldedScale) / 2
            imageLayer.frame = fitted.insetBy(dx: fitted.width * shrink, dy: fitted.height * shrink)
        }
        sequenceBadge.isHidden = content.sequenceFrames == nil
        guard content.sequenceFrames != nil else { return }
        let scale = window?.backingScaleFactor ?? 2
        sequenceCount.contentsScale = scale
        sequenceGlyph.contentsScale = scale
        sequenceArrow.contentsScale = scale
        let text = sequenceCount.preferredFrameSize()
        let glyph = JGTextStyle.mono.size + 2
        let arrow = JGTextStyle.mono.size
        let inset = JGMetrics.badgeInset
        let size = CGSize(
            width: inset + glyph + inset / 2 + text.width + inset / 2 + arrow + inset,
            height: max(text.height, glyph)
        )
        let image = imageLayer.frame
        sequenceBadge.frame = CGRect(
            x: image.maxX - inset - size.width,
            y: image.maxY - inset - size.height,
            width: size.width,
            height: size.height
        )
        sequenceGlyph.frame = CGRect(x: inset, y: (size.height - glyph) / 2, width: glyph, height: glyph)
        sequenceCount.frame = CGRect(
            x: inset + glyph + inset / 2,
            y: (size.height - text.height) / 2,
            width: text.width,
            height: text.height
        )
        sequenceArrow.frame = CGRect(x: sequenceCount.frame.maxX + inset / 2, y: (size.height - arrow) / 2, width: arrow, height: arrow)
    }

    func updateSequenceText() {
        sequenceCount.string = content.sequenceFrames.map { String($0) }
    }

    func updateSequenceColors() {
        effectiveAppearance.performAsCurrentDrawingAppearance {
            let ink = (content.sequenceUnfolded ? JGColor.accentText : JGColor.textPrimary).nsColor
            sequenceBadge.backgroundColor = JGColor.overlayScrim.nsColor.cgColor
            sequenceCount.foregroundColor = ink.cgColor
            for card in stackLayers {
                card.backgroundColor = JGColor.bgRaised.nsColor.cgColor
                card.borderColor = JGColor.lineStrong.nsColor.cgColor
            }
            let configuration = NSImage.SymbolConfiguration(pointSize: JGTextStyle.mono.size, weight: .medium)
                .applying(NSImage.SymbolConfiguration(paletteColors: [ink]))
            let symbol = NSImage(systemSymbolName: "square.stack", accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
            var rect = CGRect(origin: .zero, size: symbol?.size ?? .zero)
            sequenceGlyph.contents = symbol?.cgImage(forProposedRect: &rect, context: nil, hints: nil)
            let arrowName = content.sequenceUnfolded ? "chevron.left" : "chevron.right"
            let arrowConfiguration = NSImage.SymbolConfiguration(pointSize: JGTextStyle.mono.size - 2, weight: .bold)
                .applying(NSImage.SymbolConfiguration(paletteColors: [ink]))
            let arrow = NSImage(systemSymbolName: arrowName, accessibilityDescription: nil)?.withSymbolConfiguration(arrowConfiguration)
            var arrowRect = CGRect(origin: .zero, size: arrow?.size ?? .zero)
            sequenceArrow.contents = arrow?.cgImage(forProposedRect: &arrowRect, context: nil, hints: nil)
        }
    }
}
