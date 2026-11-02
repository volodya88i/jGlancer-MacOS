import AppKit
import JGActions
import JGDesign
import JGStore
import Observation

/// The app's file operations (docs/FEATURES.md §7): runs them on the `FileOperationQueue`, asks about name
/// conflicts, shows progress and results as toasts with Undo, keeps the undo / redo history (⌘Z / ⇧⌘Z) and the
/// recent destination folders. Nothing is ever deleted for good from here; Move to Trash is undoable.
@MainActor
@Observable
final class FileOperationsModel {
    struct Toast: Equatable {
        let id = UUID()
        var message: String
        var canUndo = false
        /// 0…1 while a long batch runs.
        var progress: Double?
        /// Show in Finder (a finished split, D-97).
        var reveal: URL?
    }

    /// A rename waiting for its new name.
    struct RenameRequest: Identifiable {
        let id = UUID()
        let url: URL
    }

    /// Several files waiting for a rename pattern.
    struct BatchRenameRequest: Identifiable {
        let id = UUID()
        let files: [BatchRenamePattern.File]
    }

    private(set) var toast: Toast?
    var renameRequest: RenameRequest?
    var batchRenameRequest: BatchRenameRequest?
    private(set) var undoStack: [UndoItem] = []
    private(set) var redoStack: [UndoItem] = []
    private(set) var recentFolders: [URL]
    private(set) var isRunning = false

    /// Called after every operation, undo and redo (cached paths are stale).
    @ObservationIgnored var onFilesChanged: (() -> Void)?
    @ObservationIgnored private let queue: FileOperationQueue
    @ObservationIgnored private let isPersistent: Bool
    @ObservationIgnored private var running: Task<Void, Never>?
    @ObservationIgnored private var dismissTask: Task<Void, Never>?

    /// Batches of at least this many files show their progress.
    static let progressThreshold = 10
    static let recentLimit = 8
    private static let recentsKey = "RecentDestinationFolders"

    init(store: LibraryStore, isPersistent: Bool) {
        queue = FileOperationQueue(index: LibraryFileIndex(store: store))
        self.isPersistent = isPersistent
        recentFolders = isPersistent
            ? (UserDefaults.standard.stringArray(forKey: Self.recentsKey) ?? []).map { URL(fileURLWithPath: $0, isDirectory: true) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
            : []
    }

    // MARK: Operations

    /// Move to… / Copy to…: `folder`, or one chosen in a panel (with New Folder).
    func transfer(_ urls: [URL], to folder: URL?, copying: Bool) {
        guard !urls.isEmpty, let folder = folder ?? chooseFolder(copying: copying) else { return }
        let conflicts = urls.filter { url in
            let target = folder.appendingPathComponent(url.lastPathComponent)
            return FileManager.default.fileExists(atPath: target.path) && target.standardizedFileURL != url.standardizedFileURL
        }
        var policy = ConflictPolicy.keepBoth
        if !conflicts.isEmpty {
            guard let chosen = askConflictPolicy(count: conflicts.count, folder: folder) else { return }
            policy = chosen
        }
        remember(folder)
        run(copying ? .copy(urls, to: folder) : .move(urls, to: folder), count: urls.count, policy: policy)
    }

    /// Makes `name` inside `parent` (undoable).
    func createFolder(named name: String, in parent: URL) {
        run(.createFolder(inside: parent, name: name), count: 1, policy: .keepBoth)
    }

    func trash(_ urls: [URL]) {
        guard !urls.isEmpty else { return }
        run(.trash(urls), count: urls.count, policy: .keepBoth)
    }

    func requestRename(_ url: URL) {
        renameRequest = RenameRequest(url: url)
    }

    /// Renames many files at once (one undo); names that cannot be used fail alone.
    func renameAll(_ items: [(URL, String)]) {
        guard !items.isEmpty else { return }
        run(.renameAll(items), count: items.count, policy: .keepBoth)
    }

    /// Renames; returns a message when the name cannot be used (the sheet shows it and stays).
    func rename(_ url: URL, to name: String) async -> String? {
        let result = await queue.perform(.rename(url, to: name))
        if !result.failures.isEmpty {
            let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
            let taken = FileManager.default.fileExists(atPath: url.deletingLastPathComponent().appendingPathComponent(trimmed).path)
            return taken
                ? String(localized: "That name is taken.", comment: "Rename: another file has this name")
                : String(localized: "That name can't be used.", comment: "Rename: empty or invalid name")
        }
        finish(result, count: 1)
        return nil
    }

    func undo() {
        guard let item = undoStack.popLast() else { return }
        run(item, redoing: false)
    }

    func redo() {
        guard let item = redoStack.popLast() else { return }
        run(item, redoing: true)
    }

    /// Records an undoable change that is not a file operation (albums); clears the redo history.
    func register(_ change: CustomUndo) {
        undoStack.append(.custom(change))
        redoStack.removeAll()
    }

    private func run(_ item: UndoItem, redoing: Bool) {
        switch item {
        case let .files(record):
            runRecord(record, redoing: redoing)
        case let .custom(change):
            Task {
                if let inverse = await change.run() {
                    if redoing {
                        undoStack.append(.custom(inverse))
                    } else {
                        redoStack.append(.custom(inverse))
                    }
                }
                show(Toast(message: redoing
                        ? String(localized: "Redone", comment: "Toast after redo")
                        : String(localized: "Undone", comment: "Toast after undo")))
            }
        }
    }

    func stop() {
        running?.cancel()
    }

    /// A one-line message (a rename that could not be done).
    func showMessage(_ message: String, reveal: URL? = nil) {
        show(Toast(message: message, reveal: reveal))
    }

    var undoTitle: String {
        undoStack.last.map(\.name) ?? ""
    }

    var redoTitle: String {
        redoStack.last.map(\.name) ?? ""
    }

    // MARK: Running

    private func run(_ operation: FileOperation, count: Int, policy: ConflictPolicy) {
        guard !isRunning else {
            NSSound.beep()
            return
        }
        isRunning = true
        dismissTask?.cancel()
        let kind = Self.kind(of: operation)
        if count >= Self.progressThreshold {
            toast = Toast(message: Self.progressMessage(kind, done: 0, total: count), progress: 0)
        }
        running = Task {
            let result = await queue.perform(operation, conflicts: policy) { progress in
                Task { @MainActor in self.showProgress(kind, progress) }
            }
            finish(result, count: count)
        }
    }

    private func runRecord(_ record: UndoRecord, redoing: Bool) {
        guard !isRunning else {
            NSSound.beep()
            return
        }
        isRunning = true
        running = Task {
            let result = await queue.perform(record)
            isRunning = false
            onFilesChanged?()
            if !result.undo.isEmpty {
                if redoing {
                    undoStack.append(.files(result.undo))
                } else {
                    redoStack.append(.files(result.undo))
                }
            }
            show(Toast(message: redoing
                    ? String(localized: "Redone", comment: "Toast after redo")
                    : String(localized: "Undone", comment: "Toast after undo")))
        }
    }

    private func finish(_ result: FileOperationResult, count _: Int) {
        isRunning = false
        onFilesChanged?()
        if !result.undo.isEmpty {
            undoStack.append(.files(result.undo))
            redoStack.removeAll()
        }
        var message = Self.doneMessage(result.undo.kind, count: result.completed)
        if !result.failures.isEmpty {
            message += " · " + String(localized: "Failed: \(result.failures.count)", comment: "Toast: files that could not be processed")
        }
        if !result.skipped.isEmpty, result.undo.kind != .rename {
            message += " · " + String(
                localized: "Skipped: \(result.skipped.count)",
                comment: "Toast: files skipped because of a name conflict"
            )
        }
        show(Toast(message: message, canUndo: !result.undo.isEmpty))
    }

    private func showProgress(_ kind: UndoRecord.Kind, _ progress: FileProgress) {
        guard isRunning, progress.total >= Self.progressThreshold else { return }
        toast = Toast(
            message: Self.progressMessage(kind, done: progress.done, total: progress.total),
            progress: Double(progress.done) / Double(max(progress.total, 1))
        )
    }

    private func show(_ newToast: Toast) {
        toast = newToast
        dismissTask?.cancel()
        dismissTask = Task {
            try? await Task.sleep(for: .seconds(JGMetrics.toastSeconds))
            guard !Task.isCancelled else { return }
            if toast?.id == newToast.id {
                toast = nil
            }
        }
    }

    // MARK: Folders and conflicts

    private func remember(_ folder: URL) {
        recentFolders.removeAll { $0.standardizedFileURL == folder.standardizedFileURL }
        recentFolders.insert(folder, at: 0)
        recentFolders = Array(recentFolders.prefix(Self.recentLimit))
        if isPersistent {
            UserDefaults.standard.set(recentFolders.map(\.path), forKey: Self.recentsKey)
        }
    }

    private func chooseFolder(copying: Bool) -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = recentFolders.first
        panel.prompt = copying
            ? String(localized: "Copy Here", comment: "Copy to… panel button")
            : String(localized: "Move Here", comment: "Move to… panel button")
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Keep Both (default), Replace (the existing files go to the Trash), Skip, or Cancel.
    private func askConflictPolicy(count: Int, folder: URL) -> ConflictPolicy? {
        let alert = NSAlert()
        alert.messageText = String(
            localized: "\(count) files already exist in “\(folder.lastPathComponent)”.",
            comment: "Name conflict alert; count and folder name"
        )
        alert.informativeText = String(localized: "Replaced files go to the Trash.", comment: "Name conflict alert")
        alert.addButton(withTitle: String(localized: "Keep Both", comment: "Name conflict: keep both files"))
        alert.addButton(withTitle: String(localized: "Replace", comment: "Name conflict: replace the existing file"))
        alert.addButton(withTitle: String(localized: "Skip", comment: "Name conflict: leave these files"))
        alert.addButton(withTitle: String(localized: "Cancel"))
        switch alert.runModal() {
        case .alertFirstButtonReturn: return .keepBoth
        case .alertSecondButtonReturn: return .replace
        case .alertThirdButtonReturn: return .skip
        default: return nil
        }
    }
}

/// Toast and menu wording of file operations.
extension FileOperationsModel {
    static func kind(of operation: FileOperation) -> UndoRecord.Kind {
        switch operation {
        case .move: .move
        case .copy: .copy
        case .rename, .renameAll: .rename
        case .trash: .trash
        case .createFolder: .createFolder
        }
    }

    static func actionName(_ kind: UndoRecord.Kind) -> String {
        switch kind {
        case .move: String(localized: "Move", comment: "Undo menu: the operation to undo")
        case .copy: String(localized: "Copy", comment: "Action: copies the files")
        case .rename: String(localized: "Rename", comment: "Undo menu: the operation to undo")
        case .trash: String(localized: "Move to Trash", comment: "Action")
        case .createFolder: String(localized: "New Folder", comment: "Undo menu: the operation to undo")
        }
    }

    static func doneMessage(_ kind: UndoRecord.Kind, count: Int) -> String {
        switch kind {
        case .move: String(localized: "Moved: \(count)", comment: "Toast after moving files")
        case .copy: String(localized: "Copied: \(count)", comment: "Toast after copying files")
        case .rename: String(localized: "Renamed", comment: "Toast after renaming a file")
        case .trash: String(localized: "Moved to Trash: \(count)", comment: "Toast after trashing files")
        case .createFolder: String(localized: "Folder created", comment: "Toast after creating a folder")
        }
    }

    static func progressMessage(_ kind: UndoRecord.Kind, done: Int, total: Int) -> String {
        switch kind {
        case .copy: String(localized: "Copying \(done) of \(total)…", comment: "Toast while copying files")
        case .trash: String(localized: "Moving to Trash \(done) of \(total)…", comment: "Toast while trashing files")
        default: String(localized: "Moving \(done) of \(total)…", comment: "Toast while moving files")
        }
    }
}

/// One step of the undo / redo history: a file operation or another change (albums).
@MainActor
enum UndoItem {
    case files(UndoRecord)
    case custom(CustomUndo)

    /// For "Undo …" in the Edit menu.
    var name: String {
        switch self {
        case let .files(record): FileOperationsModel.actionName(record.kind)
        case let .custom(change): change.name
        }
    }
}

/// An undoable change outside the file system: running it undoes (or redoes) the change and returns its inverse.
struct CustomUndo {
    let name: String
    let run: @MainActor () async -> CustomUndo?
}
