import Foundation

/// One reversible file change. Running a step returns the step that undoes it, so an operation's undo record
/// is the inverses of its steps in reverse order, and undoing an undo record yields the redo record.
public enum FileStep: Equatable, Sendable {
    /// Moves a file (another volume: copy, verify, then delete the source). Undo: move back.
    case move(from: URL, to: URL)
    /// Copies a file. Undo: trash the copy.
    case copy(from: URL, to: URL)
    /// Moves a file to the Trash. Undo: restore it.
    case trash(URL)
    /// Moves a file out of the Trash to where it was. Undo: trash it again.
    case restore(from: URL, to: URL)
    /// Creates an empty folder. Undo: trash it.
    case createFolder(URL)
}

/// What undoes (or redoes) one operation.
public struct UndoRecord: Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case move
        case copy
        case rename
        case trash
        case createFolder
    }

    public let kind: Kind
    /// Steps to run in order.
    public let steps: [FileStep]

    public init(kind: Kind, steps: [FileStep]) {
        self.kind = kind
        self.steps = steps
    }

    public var isEmpty: Bool {
        steps.isEmpty
    }
}
