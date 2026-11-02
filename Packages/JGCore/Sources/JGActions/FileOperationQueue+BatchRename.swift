import Foundation

/// Batch rename (`FileOperation.renameAll`).
extension FileOperationQueue {
    /// Every name is checked before anything moves: an invalid or duplicate name, or one another file in the folder
    /// has, fails that item, and then every item that wanted the failed file's name fails too. Files whose name
    /// another file of the batch takes first move to a hidden temporary name (so swaps and shifts work), then every
    /// file gets its new name. Should a move still fail, the file returns to its old name, or a free one next to
    /// it, never staying hidden. One undo record covers everything done.
    func renameAll(_ items: [(URL, String)], _ progress: (@Sendable (FileProgress) -> Void)?) async -> FileOperationResult {
        var result = FileOperationResult(kind: .rename)
        let targets = items
            .map { $0.0.deletingLastPathComponent().appendingPathComponent($0.1.trimmingCharacters(in: .whitespacesAndNewlines)) }
        let failed = renameFailures(items, targets)
        var steps: [FileStep] = []
        var current = items.map(\.0)
        let wanted = Set(items.indices.filter { !failed.contains($0) }.map { targets[$0].path.lowercased() })
        for index in items.indices where !failed.contains(index) && wanted.contains(current[index].path.lowercased())
            && targets[index].path.lowercased() != current[index].path.lowercased()
        {
            let temporary = current[index].deletingLastPathComponent().appendingPathComponent(".jglancer-rename-\(UUID().uuidString)")
            if let step = try? await run(.move(from: current[index], to: temporary)) {
                steps.append(step)
                current[index] = temporary
            }
        }
        for index in items.indices {
            let source = items[index].0
            if failed.contains(index) {
                result.failures.append(source)
            } else if let (undo, location) = try? await rename(current[index], to: items[index].1, originalName: source.lastPathComponent) {
                steps += undo
                if let location {
                    result.completed += 1
                    result.results.append(location)
                } else {
                    result.skipped.append(source)
                }
            } else {
                if current[index] != source, let step = try? await run(.move(from: current[index], to: unique(source))) {
                    steps.append(step)
                }
                result.failures.append(source)
            }
            progress?(FileProgress(done: index + 1, total: items.count))
        }
        result.undo = UndoRecord(kind: .rename, steps: steps.reversed())
        return result
    }

    /// Items of a batch rename that cannot be done (see `renameAll`).
    private func renameFailures(_ items: [(URL, String)], _ targets: [URL]) -> Set<Int> {
        let sources = Set(items.map { $0.0.path.lowercased() })
        var counts: [String: Int] = [:]
        for target in targets {
            counts[target.path.lowercased(), default: 0] += 1
        }
        var failed = Set(items.indices.filter { index in
            let name = targets[index].lastPathComponent
            let key = targets[index].path.lowercased()
            return name.isEmpty || name.contains(":") || name.hasPrefix(".") || items[index].1.contains("/")
                || counts[key, default: 0] > 1 || (fileSystem.exists(targets[index]) && !sources.contains(key))
        })
        // A file that stays keeps its name: whoever wanted that name fails too.
        while true {
            let kept = Set(failed.map { items[$0].0.path.lowercased() })
            let more = items.indices.filter { !failed.contains($0) && kept.contains(targets[$0].path.lowercased())
                && targets[$0].path.lowercased() != items[$0].0.path.lowercased()
            }
            guard !more.isEmpty else { return failed }
            failed.formUnion(more)
        }
    }
}
