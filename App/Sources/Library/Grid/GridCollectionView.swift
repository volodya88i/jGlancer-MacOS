import AppKit
import Carbon.HIToolbox
import JGModel

/// The grid's collection view. Selection is owned by the model, so built-in selection is off and
/// mouse and keyboard input go to the controller (standard AppKit responder actions for keys).
final class GridCollectionView: NSCollectionView {
    weak var controller: GridController?

    override var acceptsFirstResponder: Bool {
        true
    }

    // Reordering an album: only the grid's own drags, only in an album (GridController+AlbumOrder).

    override func draggingEntered(_ sender: any NSDraggingInfo) -> NSDragOperation {
        controller?.albumDragUpdated(sender) ?? []
    }

    override func draggingUpdated(_ sender: any NSDraggingInfo) -> NSDragOperation {
        controller?.albumDragUpdated(sender) ?? []
    }

    override func draggingExited(_: (any NSDraggingInfo)?) {
        controller?.albumDragEnded()
    }

    override func performDragOperation(_ sender: any NSDraggingInfo) -> Bool {
        controller?.performAlbumDrop(sender) ?? false
    }

    override func menu(for event: NSEvent) -> NSMenu? {
        controller?.contextMenu(for: event)
    }

    /// Edit ▸ Copy (⌘C): the selected files, ready to paste in Finder.
    @objc func copy(_: Any?) {
        controller?.model.performAction?(.copy)
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        controller?.mouseDown(event)
    }

    override func keyDown(with event: NSEvent) {
        if event.specialKey == .f2 {
            controller?.model.performAction?(.rename)
            return
        }
        // F (by key position, so any layout) toggles Quick Preview's full screen while it is open.
        if event.keyCode == UInt16(kVK_ANSI_F), event.modifierFlags.isDisjoint(with: [.command, .control, .option, .shift]),
           controller?.model.onQuickPreviewKey?(.fullScreen) == true
        {
            return
        }
        interpretKeyEvents([event])
    }

    /// Space toggles Quick Preview; other typing is not handled yet (type-select comes later); no beep.
    override func insertText(_ text: Any) {
        if (text as? String) == " " {
            _ = controller?.model.onQuickPreviewKey?(.space)
        }
    }

    override func moveLeft(_: Any?) {
        controller?.move(.left, extending: false)
    }

    override func moveRight(_: Any?) {
        controller?.move(.right, extending: false)
    }

    override func moveUp(_: Any?) {
        controller?.move(.up, extending: false)
    }

    override func moveDown(_: Any?) {
        controller?.move(.down, extending: false)
    }

    override func moveLeftAndModifySelection(_: Any?) {
        controller?.move(.left, extending: true)
    }

    override func moveRightAndModifySelection(_: Any?) {
        controller?.move(.right, extending: true)
    }

    override func moveUpAndModifySelection(_: Any?) {
        controller?.move(.up, extending: true)
    }

    override func moveDownAndModifySelection(_: Any?) {
        controller?.move(.down, extending: true)
    }

    override func scrollPageUp(_: Any?) {
        controller?.move(.pageUp, extending: false)
    }

    override func scrollPageDown(_: Any?) {
        controller?.move(.pageDown, extending: false)
    }

    override func pageUpAndModifySelection(_: Any?) {
        controller?.move(.pageUp, extending: true)
    }

    override func pageDownAndModifySelection(_: Any?) {
        controller?.move(.pageDown, extending: true)
    }

    override func scrollToBeginningOfDocument(_: Any?) {
        controller?.move(.home, extending: false)
    }

    override func scrollToEndOfDocument(_: Any?) {
        controller?.move(.end, extending: false)
    }

    override func moveToBeginningOfDocument(_: Any?) {
        controller?.move(.home, extending: false)
    }

    override func moveToEndOfDocument(_: Any?) {
        controller?.move(.end, extending: false)
    }

    override func moveToBeginningOfDocumentAndModifySelection(_: Any?) {
        controller?.move(.home, extending: true)
    }

    override func moveToEndOfDocumentAndModifySelection(_: Any?) {
        controller?.move(.end, extending: true)
    }

    /// Return pauses Quick Preview while it is open, else opens the viewer.
    override func insertNewline(_: Any?) {
        if controller?.model.onQuickPreviewKey?(.returnKey) != true {
            controller?.openFocused()
        }
    }

    override func selectAll(_: Any?) {
        controller?.selectAll()
    }

    /// Esc closes Quick Preview first, then clears the selection.
    /// Delete (⌫) removes the selection from the album shown; files stay. Outside albums it does nothing.
    override func deleteBackward(_: Any?) {
        guard controller?.model.state.albumID != nil else { return }
        controller?.model.performAction?(.removeFromAlbum)
    }

    override func cancelOperation(_: Any?) {
        if controller?.model.onQuickPreviewKey?(.escape) != true {
            controller?.clearSelection()
        }
    }
}

extension GridCollectionView: NSMenuItemValidation {
    func validateMenuItem(_ item: NSMenuItem) -> Bool {
        if item.action == #selector(copy(_:)) {
            return controller?.model.selection.isEmpty == false
        }
        return true
    }
}
