import AppKit
import JGDesign

/// The name being edited in place: its field, item and file.
struct GridRenameState {
    let field: NSTextField
    let id: Int64
    let url: URL
}

/// Renaming in place, like Finder (docs/FEATURES.md §7): the caption becomes a field with the name before the
/// extension selected; Return or a click elsewhere commits, Esc cancels.
extension GridController: NSTextFieldDelegate {
    func beginRename(_ id: Int64) {
        endRename(commit: false)
        guard let index = model.order.index(of: id), let url = rows[id]?.url else { return }
        scrollToVisible(index)
        collectionView.layoutSubtreeIfNeeded()
        let frame = collectionView.frameForItem(at: index)
        guard frame.width > 0 else { return }
        let field = NSTextField(string: url.lastPathComponent)
        field.font = NSFont.systemFont(ofSize: JGTextStyle.body.size)
        field.alignment = .center
        field.isBordered = false
        field.drawsBackground = true
        field.backgroundColor = JGColor.bgBase.nsColor
        field.textColor = JGColor.textPrimary.nsColor
        field.focusRingType = .exterior
        field.cell?.wraps = true
        field.cell?.isScrollable = false
        field.maximumNumberOfLines = 0
        field.delegate = self
        collectionView.addSubview(field)
        renaming = GridRenameState(field: field, id: id, url: url)
        position(field, under: frame)
        collectionView.window?.makeFirstResponder(field)
        let base = (url.lastPathComponent as NSString).deletingPathExtension
        field.currentEditor()?.selectedRange = NSRange(location: 0, length: (base as NSString).length)
    }

    /// Below the tile's square, a little wider than the tile, as tall as the wrapped name.
    private func position(_ field: NSTextField, under frame: NSRect) {
        let side = frame.width
        let width = side + 2 * JGMetrics.badgeInset
        let fitting = field.cell?.cellSize(forBounds: NSRect(x: 0, y: 0, width: width, height: .greatestFiniteMagnitude)).height ?? 0
        field.frame = NSRect(
            x: frame.minX - JGMetrics.badgeInset, y: frame.minY + side + JGMetrics.badgeInset,
            width: width, height: max(JGMetrics.tileCaptionHeight, ceil(fitting))
        )
    }

    func endRename(commit: Bool) {
        guard let state = renaming else { return }
        renaming = nil
        let field = state.field
        let url = state.url
        let name = field.stringValue
        field.delegate = nil
        field.removeFromSuperview()
        collectionView.window?.makeFirstResponder(collectionView)
        if commit, name != url.lastPathComponent {
            model.onInlineRename?(url, name)
        }
    }

    func controlTextDidChange(_: Notification) {
        guard let state = renaming, let index = model.order.index(of: state.id) else { return }
        position(state.field, under: collectionView.frameForItem(at: index))
    }

    func control(_: NSControl, textView _: NSTextView, doCommandBy selector: Selector) -> Bool {
        switch selector {
        case #selector(NSResponder.cancelOperation(_:)):
            endRename(commit: false)
            return true
        case #selector(NSResponder.insertNewline(_:)):
            endRename(commit: true)
            return true
        default:
            return false
        }
    }

    /// A click elsewhere (or Tab) commits.
    func controlTextDidEndEditing(_: Notification) {
        endRename(commit: true)
    }
}
