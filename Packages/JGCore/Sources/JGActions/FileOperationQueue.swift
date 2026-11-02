import Foundation

/// A file operation the user asked for (docs/FEATURES.md §7).
public enum FileOperation: Sendable {
    case move([URL], to: URL)
    case copy([URL], to: URL)
    case rename(URL, to: String)
    /// Many renames as one undoable batch (`BatchRenamePattern`); names may trade places.
    case renameAll([(URL, String)])
    case trash([URL])
    case createFolder(inside: URL, name: String)
}

/// Keeps the library index in step with file operations (asset ids survive moves).
public protocol FileIndex: Sendable {
    func moved(from source: URL, to destination: URL) async
    /// Trashed, or moved out of view.
    func removed(_ url: URL) async
    /// Restored from the Trash.
    func restored(_ url: URL) async
}

/// How a batch went.
public struct FileOperationResult: Sendable {
    /// Items done.
    public var completed = 0
    public var skipped: [URL] = []
    public var failures: [URL] = []
    public var wasCancelled = false
    /// Where the done items are now (moved, copied, renamed, restored or created).
    public var results: [URL] = []
    /// Undoes what was done (empty when nothing was).
    public var undo: UndoRecord

    public init(kind: UndoRecord.Kind) {
        undo = UndoRecord(kind: kind, steps: [])
    }
}

/// Progress of a batch: items finished of the total.
public struct FileProgress: Sendable, Equatable {
    public let done: Int
    public let total: Int
}

public enum FileOperationError: Error, Equatable, Sendable {
    case nameTaken
    case invalidName
    case verificationFailed
}

/// Runs file operations one item at a time (docs/ARCHITECTURE.md §12). Same-volume moves are renames; a move to
/// another volume copies to a temporary name, verifies size and quick hash, places the copy, and only then
/// deletes the source. Copies also go through a temporary name, so a failure or a cancel never leaves a partial
/// file. Conflicts follow the batch's policy; replaced files go to the Trash. Completed items stay done when a
/// later one fails or the batch is cancelled; the result's undo record reverses exactly what was done.
public actor FileOperationQueue {
    let fileSystem: any FileSystem
    private let index: (any FileIndex)?

    public init(fileSystem: any FileSystem = LocalFileSystem(), index: (any FileIndex)? = nil) {
        self.fileSystem = fileSystem
        self.index = index
    }

    public func perform(
        _ operation: FileOperation, conflicts policy: ConflictPolicy = .keepBoth,
        progress: (@Sendable (FileProgress) -> Void)? = nil
    ) async -> FileOperationResult {
        switch operation {
        case let .move(sources, folder):
            await batch(.move, sources, progress) { try await self.transfer($0, to: folder, policy, copying: false) }
        case let .copy(sources, folder):
            await batch(.copy, sources, progress) { try await self.transfer($0, to: folder, policy, copying: true) }
        case let .rename(source, name):
            await batch(.rename, [source], progress) { try await self.rename($0, to: name) }
        case let .renameAll(items):
            await renameAll(items, progress)
        case let .trash(sources):
            await batch(.trash, sources, progress) { source in
                let undo = try await self.run(.trash(source))
                if case let .restore(trashed, _) = undo {
                    return ([undo], trashed)
                }
                return ([undo], source)
            }
        case let .createFolder(parent, name):
            await batch(.createFolder, [parent], progress) { parent in
                let folder = self.unique(parent.appendingPathComponent(name, isDirectory: true))
                let undo = try await self.run(.createFolder(folder))
                return ([undo], folder)
            }
        }
    }

    /// Runs an undo (or redo) record; the result's record redoes (or undoes) it again.
    public func perform(_ record: UndoRecord, progress: (@Sendable (FileProgress) -> Void)? = nil) async -> FileOperationResult {
        var result = FileOperationResult(kind: record.kind)
        var inverses: [FileStep] = []
        for (number, step) in record.steps.enumerated() {
            if Task.isCancelled {
                result.wasCancelled = true
                break
            }
            do {
                try await inverses.append(run(step))
                result.completed += 1
            } catch {
                result.failures.append(Self.subject(of: step))
            }
            progress?(FileProgress(done: number + 1, total: record.steps.count))
        }
        result.undo = UndoRecord(kind: record.kind, steps: inverses.reversed())
        return result
    }

    // MARK: Batches

    /// Runs `item` for each source; each returns its undo steps (in run order) and where the item is now.
    private func batch(
        _ kind: UndoRecord.Kind, _ sources: [URL], _ progress: (@Sendable (FileProgress) -> Void)?,
        _ item: (URL) async throws -> ([FileStep], URL?)
    ) async -> FileOperationResult {
        var result = FileOperationResult(kind: kind)
        var inverses: [FileStep] = []
        for (number, source) in sources.enumerated() {
            if Task.isCancelled {
                result.wasCancelled = true
                break
            }
            do {
                let (undo, location) = try await item(source)
                if let location {
                    inverses += undo
                    result.completed += 1
                    result.results.append(location)
                } else {
                    result.skipped.append(source)
                }
            } catch {
                result.failures.append(source)
            }
            progress?(FileProgress(done: number + 1, total: sources.count))
        }
        result.undo = UndoRecord(kind: kind, steps: inverses.reversed())
        return result
    }

    /// Moves or copies one file into `folder`, resolving a name conflict by `policy`. Returns nil to skip.
    private func transfer(
        _ source: URL, to folder: URL, _ policy: ConflictPolicy, copying: Bool
    ) async throws -> ([FileStep], URL?) {
        var destination = folder.appendingPathComponent(source.lastPathComponent)
        if !copying, destination.standardizedFileURL == source.standardizedFileURL {
            return ([], nil)
        }
        var undo: [FileStep] = []
        if fileSystem.exists(destination) {
            switch policy {
            case .skip:
                return ([], nil)
            case .keepBoth:
                destination = unique(destination)
            case .replace:
                try await undo.append(run(.trash(destination)))
            }
        }
        try await undo.append(run(copying ? .copy(from: source, to: destination) : .move(from: source, to: destination)))
        return (undo, destination)
    }

    func rename(_ source: URL, to name: String, originalName: String? = nil) async throws -> ([FileStep], URL?) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains("/"), !trimmed.contains(":"), !trimmed.hasPrefix(".") else {
            throw FileOperationError.invalidName
        }
        let destination = source.deletingLastPathComponent().appendingPathComponent(trimmed)
        guard destination.lastPathComponent != source.lastPathComponent else { return ([], nil) }
        // A case-only change of the same file is allowed; anything else that exists is taken.
        let caseOnly = trimmed.lowercased() == (originalName ?? source.lastPathComponent).lowercased()
        if fileSystem.exists(destination), !caseOnly {
            throw FileOperationError.nameTaken
        }
        let undo = try await run(.move(from: source, to: destination))
        return ([undo], destination)
    }

    // MARK: Steps

    /// Runs one step and returns its inverse.
    func run(_ step: FileStep) async throws -> FileStep {
        switch step {
        case let .move(source, destination):
            try move(source, to: destination)
            await index?.moved(from: source, to: destination)
            return .move(from: destination, to: source)
        case let .copy(source, destination):
            try copyVerified(source, to: destination)
            return .trash(destination)
        case let .trash(url):
            let trashed = try fileSystem.trash(url)
            await index?.removed(url)
            return .restore(from: trashed, to: url)
        case let .restore(trashed, original):
            let destination = fileSystem.exists(original) ? unique(original) : original
            try fileSystem.move(trashed, to: destination)
            await index?.restored(destination)
            return .trash(destination)
        case let .createFolder(url):
            try fileSystem.createDirectory(url)
            return .trash(url)
        }
    }

    private func move(_ source: URL, to destination: URL) throws {
        guard !fileSystem.exists(destination) || destination.path.lowercased() == source.path.lowercased() else {
            throw FileOperationError.nameTaken
        }
        let sameVolume = fileSystem.volume(of: source) == fileSystem.volume(of: destination.deletingLastPathComponent())
        if sameVolume {
            try fileSystem.move(source, to: destination)
            return
        }
        try copyVerified(source, to: destination)
        do {
            try fileSystem.remove(source)
        } catch {
            // Both copies exist: take the new one back so the move did not happen.
            try? fileSystem.remove(destination)
            throw error
        }
    }

    /// Copies through a temporary name next to the destination, checks size and quick hash, then places it.
    private func copyVerified(_ source: URL, to destination: URL) throws {
        guard !fileSystem.exists(destination) else { throw FileOperationError.nameTaken }
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".jglancer-\(UUID().uuidString)-\(destination.lastPathComponent)")
        try fileSystem.copy(source, to: temporary)
        guard fileSystem.size(of: temporary) == fileSystem.size(of: source),
              fileSystem.quickHash(of: temporary) == fileSystem.quickHash(of: source)
        else {
            try? fileSystem.remove(temporary)
            throw FileOperationError.verificationFailed
        }
        do {
            try fileSystem.move(temporary, to: destination)
        } catch {
            try? fileSystem.remove(temporary)
            throw error
        }
    }

    /// `url`, or "name 2.ext", "name 3.ext", … if taken.
    func unique(_ url: URL) -> URL {
        guard fileSystem.exists(url) else { return url }
        let folder = url.deletingLastPathComponent()
        let ext = url.pathExtension
        let base = url.deletingPathExtension().lastPathComponent
        var number = 2
        while true {
            let name = ext.isEmpty ? "\(base) \(number)" : "\(base) \(number).\(ext)"
            let candidate = folder.appendingPathComponent(name, isDirectory: url.hasDirectoryPath)
            if !fileSystem.exists(candidate) {
                return candidate
            }
            number += 1
        }
    }

    private static func subject(of step: FileStep) -> URL {
        switch step {
        case let .move(source, _), let .copy(source, _), let .restore(source, _): source
        case let .trash(url), let .createFolder(url): url
        }
    }
}
