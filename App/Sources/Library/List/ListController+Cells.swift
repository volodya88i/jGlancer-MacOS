import AppKit
import JGDesign
import JGModel
import JGThumbs
import UniformTypeIdentifiers

/// The list's cells: thumbnails and glyphs, the columns' text (D-125).
extension ListController {
    // MARK: Cells

    func nameCell(for item: ListItem, in outlineView: NSOutlineView) -> NSView {
        let cell = outlineView.makeView(withIdentifier: ListNameCell.identifier, owner: nil) as? ListNameCell
            ?? ListNameCell(frame: .zero)
        cell.identifier = ListNameCell.identifier
        cell.effectiveAppearance.performAsCurrentDrawingAppearance {
            cell.label.textColor = JGColor.textPrimary.nsColor
        }
        switch item.row {
        case let .folder(id):
            cell.label.stringValue = outline.folders[id]?.name ?? ""
            cell.setImage(nil, glyph: Self.glyph("folder", appearance: cell.effectiveAppearance))
        case let .asset(id):
            cell.assetID = id
            guard let asset = asset(id) else {
                cell.label.stringValue = ""
                cell.setImage(nil, glyph: nil)
                return cell
            }
            cell.label.stringValue = asset.name
            cell.star.image = asset.flag == .none ? nil : asset.flag.starImage(
                pointSize: JGMetrics.flagStarSize, appearance: cell.effectiveAppearance
            )
            showThumbnail(of: asset, in: cell)
        }
        cell.needsLayout = true
        return cell
    }

    func textCell(_ column: ListColumn, for item: ListItem, in outlineView: NSOutlineView) -> NSView {
        let cell = outlineView.makeView(withIdentifier: ListTextCell.identifier, owner: nil) as? ListTextCell
            ?? ListTextCell(frame: .zero)
        cell.identifier = ListTextCell.identifier
        let mono = column == .date || column == .size
        cell.label.font = mono
            ? NSFont.monospacedDigitSystemFont(ofSize: JGTextStyle.mono.size, weight: .regular)
            : NSFont.systemFont(ofSize: JGTextStyle.body.size)
        cell.label.alignment = column == .size ? .right : .left
        cell.effectiveAppearance.performAsCurrentDrawingAppearance {
            cell.label.textColor = JGColor.textSecondary.nsColor
        }
        cell.label.stringValue = text(column, for: item)
        cell.needsLayout = true
        return cell
    }

    private func text(_ column: ListColumn, for item: ListItem) -> String {
        switch item.row {
        case let .folder(id): folderText(column, id)
        case let .asset(id): asset(id).map { assetText(column, $0) } ?? ""
        }
    }

    private func folderText(_ column: ListColumn, _ id: Int64) -> String {
        switch column {
        case .date: folderDates[id].map(Self.dateText) ?? ""
        case .size: "--"
        case .kind: String(localized: "Folder", comment: "List view: the kind of a folder row")
        case .name: outline.folders[id]?.name ?? ""
        }
    }

    private func assetText(_ column: ListColumn, _ asset: Asset) -> String {
        switch column {
        case .date: Self.dateText(asset.modifiedAt)
        case .size: ByteCountFormatter.string(fromByteCount: asset.size, countStyle: .file)
        case .kind: kindText(of: asset)
        case .name: asset.name
        }
    }

    private func kindText(of asset: Asset) -> String {
        let type = Self.typeName(asset.typeIdentifier) ?? GridController.kindName(asset.kind)
        guard let frames = model.sequence(headedBy: asset.id)?.frames.count, model.isFolded(asset.id) else { return type }
        return String(localized: "Image sequence (\(frames))", comment: "List view: the kind of a folded image sequence; the frame count")
    }

    private func showThumbnail(of asset: Asset, in cell: ListNameCell) {
        let symbol = switch asset.kind {
        case _ where asset.isCloudOnly: "icloud"
        case .photo: "photo"
        case .video: "film"
        case .audio: "waveform"
        }
        let glyph = Self.glyph(symbol, appearance: cell.effectiveAppearance)
        let scale = outlineView.window?.backingScaleFactor ?? 2
        let request = ThumbnailRequest(
            assetID: asset.id, url: asset.url, kind: asset.kind, typeIdentifier: asset.typeIdentifier,
            modifiedAt: asset.modifiedAt, duration: asset.duration,
            bucket: ThumbnailBucket.covering(longestSidePixels: Int(outlineView.rowHeight * scale))
        )
        let service = model.thumbnails
        if let cached = service.cachedThumbnail(for: request) {
            cell.setImage(cached, glyph: glyph)
            return
        }
        cell.setImage(nil, glyph: glyph)
        let id = asset.id
        if asset.isCloudOnly {
            // Kept only in the cloud: a stored thumbnail shows, none is made (D-124).
            guard cloudLookups.insert(id).inserted else { return }
        }
        cell.thumbnailTask = Task { [weak cell] in
            let image = asset.isCloudOnly ? await service.storedThumbnail(for: request)
                : await service.thumbnail(for: request, priority: .visible)
            guard !Task.isCancelled, let cell, cell.assetID == id, let image else { return }
            cell.setImage(image, glyph: glyph)
        }
    }

    // MARK: Formatting

    static func dateText(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    private static var typeNames: [String: String] = [:]

    /// "JPEG image", "Waveform audio", as Finder names the type.
    static func typeName(_ identifier: String?) -> String? {
        guard let identifier else { return nil }
        if let known = typeNames[identifier] {
            return known
        }
        let name = UTType(identifier)?.localizedDescription
        typeNames[identifier] = name
        return name
    }

    private static var glyphs: [String: CGImage] = [:]

    static func glyph(_ symbol: String, appearance: NSAppearance) -> CGImage? {
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let key = "\(symbol)-\(isDark)"
        if let cached = glyphs[key] {
            return cached
        }
        var color = NSColor.gray
        appearance.performAsCurrentDrawingAppearance {
            color = JGColor.textSecondary.nsColor.usingColorSpace(.sRGB) ?? .gray
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: JGTextStyle.body.size, weight: .regular)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: nil)?.withSymbolConfiguration(configuration)
        var rect = CGRect(origin: .zero, size: image?.size ?? .zero)
        let rendered = image?.cgImage(forProposedRect: &rect, context: nil, hints: nil)
        glyphs[key] = rendered
        return rendered
    }
}
