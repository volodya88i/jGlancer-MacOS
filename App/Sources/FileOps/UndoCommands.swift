import AppKit
import SwiftUI

/// Edit ▸ Undo / Redo for file operations (⌘Z / ⇧⌘Z). While a text field edits, they go to the field instead.
struct UndoCommands: Commands {
    let appModel: AppModel

    var body: some Commands {
        CommandGroup(replacing: .undoRedo) {
            let fileOps = appModel.fileOps
            Button {
                if !Self.forwardToTextField(#selector(UndoManager.undo)) {
                    fileOps?.undo()
                }
            } label: {
                Text("Undo \(fileOps?.undoTitle ?? "")", comment: "Edit menu; the argument names the operation")
            }
            .keyboardShortcut("z", modifiers: .command)
            .disabled(fileOps?.undoStack.isEmpty != false && !Self.isEditingText)
            Button {
                if !Self.forwardToTextField(#selector(UndoManager.redo)) {
                    fileOps?.redo()
                }
            } label: {
                Text("Redo \(fileOps?.redoTitle ?? "")", comment: "Edit menu; the argument names the operation")
            }
            .keyboardShortcut("z", modifiers: [.command, .shift])
            .disabled(fileOps?.redoStack.isEmpty != false && !Self.isEditingText)
        }
    }

    private static var isEditingText: Bool {
        NSApp.keyWindow?.firstResponder is NSText
    }

    /// Sends undo / redo to a focused text field; false when none is focused.
    private static func forwardToTextField(_ action: Selector) -> Bool {
        guard isEditingText else { return false }
        return NSApp.sendAction(action, to: nil, from: nil)
    }
}
