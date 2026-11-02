import Foundation

/// A directory to rescan after file-system events.
public struct RescanTarget: Hashable, Sendable {
    /// Path relative to the root, empty for the root.
    public let relativePath: String
    /// Whether subdirectories are rescanned too.
    public let recursive: Bool

    public init(relativePath: String, recursive: Bool) {
        self.relativePath = relativePath
        self.recursive = recursive
    }
}

/// Turns a batch of FSEvents into the smallest set of directory rescans (pure; no IO).
public enum ChangePlanner {
    /// Rescans needed for `events` under `rootPath`. Events in hidden items are ignored.
    public static func plan(_ events: [FileSystemEvent], rootPath: String) -> [RescanTarget] {
        var targets = Set<RescanTarget>()
        for event in events where !event.flags.contains(.historyDone) {
            if event.flags.requiresFullRescan {
                return [RescanTarget(relativePath: "", recursive: true)]
            }
            guard let relative = relativePath(of: event.path, rootPath: rootPath), !isHidden(relative) else { continue }
            if event.flags.contains(.mustScanSubDirs) {
                targets.insert(RescanTarget(relativePath: relative, recursive: true))
                continue
            }
            if relative.isEmpty {
                targets.insert(RescanTarget(relativePath: "", recursive: false))
                continue
            }
            targets.insert(RescanTarget(relativePath: parent(of: relative), recursive: false))
            if event.flags.contains(.itemIsDirectory) {
                targets.insert(RescanTarget(relativePath: relative, recursive: true))
            }
        }
        return coalesce(targets)
    }

    /// Drops targets already covered by a recursive rescan of an ancestor (or of the same directory).
    static func coalesce(_ targets: Set<RescanTarget>) -> [RescanTarget] {
        let recursive = targets.filter(\.recursive).map(\.relativePath)
        func covered(_ target: RescanTarget) -> Bool {
            recursive.contains { ancestor in
                if ancestor == target.relativePath {
                    return !target.recursive
                }
                return ancestor.isEmpty || target.relativePath.hasPrefix(ancestor + "/")
            }
        }
        return targets.filter { !covered($0) }.sorted { $0.relativePath < $1.relativePath }
    }

    static func relativePath(of path: String, rootPath: String) -> String? {
        let trimmed = path.hasSuffix("/") ? String(path.dropLast()) : path
        if trimmed == rootPath {
            return ""
        }
        guard trimmed.hasPrefix(rootPath + "/") else { return nil }
        return String(trimmed.dropFirst(rootPath.count + 1))
    }

    static func parent(of relativePath: String) -> String {
        (relativePath as NSString).deletingLastPathComponent
    }

    static func isHidden(_ relativePath: String) -> Bool {
        relativePath.split(separator: "/").contains { $0.hasPrefix(".") }
    }
}
