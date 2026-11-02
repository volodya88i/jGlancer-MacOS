import Foundation
import JGModel
import JGStore
import os

/// Indexes library roots: stage 1 (directory listing), stage 2 (metadata) and live watching
/// (docs/ARCHITECTURE.md §5). Only reads files; never modifies them.
public actor LibraryScanner {
    public nonisolated let store: LibraryStore
    /// Held by the photo viewer while it decodes: metadata extraction waits (D-82).
    public nonisolated let pause = PauseGate()
    private let lister: DirectoryLister
    private let extractor: MetadataExtractor
    private let watcher: FolderWatcher
    private let probe = DiskFileProbe()
    private let signposter = OSSignposter(subsystem: "JGCore", category: "scan")

    public init(
        store: LibraryStore,
        lister: DirectoryLister = DirectoryLister(),
        extractor: MetadataExtractor = MetadataExtractor(),
        watcher: FolderWatcher = FolderWatcher()
    ) {
        self.store = store
        self.lister = lister
        self.extractor = extractor
        self.watcher = watcher
    }

    // MARK: Roots

    /// Adds `url` as a library root and runs stage 1 on it.
    public func addRoot(at url: URL, isRecursive: Bool = true) async throws -> (RootFolder, ScanReport) {
        let root = try await registerRoot(at: url, isRecursive: isRecursive)
        return try await (root, scan(rootID: root.id))
    }

    /// Adds `url` as a library root without scanning it (`watch` scans it first).
    public func registerRoot(at url: URL, isRecursive: Bool = true) async throws -> RootFolder {
        let resolved = URL(fileURLWithPath: CanonicalPath.of(url), isDirectory: true)
        let values = try? resolved.resourceValues(forKeys: [.isDirectoryKey, .volumeUUIDStringKey])
        guard values?.isDirectory == true else { throw ScanError.rootUnavailable(path: resolved.path) }
        let bookmark = (try? resolved.bookmarkData(options: .withSecurityScope))
            ?? (try? resolved.bookmarkData())
        return try await store.addRoot(
            path: resolved.path, bookmark: bookmark, volumeUUID: values?.volumeUUIDString, isRecursive: isRecursive
        )
    }

    // MARK: Stage 1

    /// Diff-scans a whole root against the database; `progress` hears after every folder listed.
    public func scan(rootID: Int64, progress: (@Sendable (ScanProgress) -> Void)? = nil) async throws -> ScanReport {
        let root = try await store.root(id: rootID)
        guard directoryExists(root.url) else { throw ScanError.rootUnavailable(path: root.path) }
        return try await scan(root: root, relativePath: "", recursive: root.isRecursive, progress: progress)
    }

    private func scan(
        root: RootFolder, relativePath: String, recursive: Bool, progress: (@Sendable (ScanProgress) -> Void)? = nil
    ) async throws -> ScanReport {
        let state = signposter.beginInterval("scan.stage1", id: signposter.makeSignpostID(), "\(root.path)/\(relativePath)")
        defer { signposter.endInterval("scan.stage1", state) }
        let start = Date()
        var report = ScanReport()
        var found = ScanProgress()
        var queue = [relativePath]
        while let current = queue.popLast() {
            try Task.checkCancellation()
            let directory = Self.url(root: root, relativePath: current)
            let listing: DirectoryScan
            do {
                listing = try lister.list(directory, rootID: root.id, relativePath: current)
            } catch {
                report.unreadableDirectories += 1
                continue
            }
            try await report.add(store.applyDirectoryScan(listing, probe: probe))
            found.files += listing.files.count
            found.folders += 1
            progress?(found)
            if recursive {
                queue += listing.subdirectories.map { current.isEmpty ? $0 : current + "/" + $0 }
            }
        }
        report.duration = Date().timeIntervalSince(start)
        return report
    }

    // MARK: Stage 2

    /// Extracts metadata for every pending asset, `concurrency` files at a time at utility priority.
    /// Returns the number of assets processed. Cancellable between files.
    public func extractMetadata(
        batchSize: Int = 128,
        concurrency: Int = max(2, ProcessInfo.processInfo.activeProcessorCount / 2)
    ) async throws -> Int {
        let state = signposter.beginInterval("scan.stage2")
        defer { signposter.endInterval("scan.stage2", state) }
        var afterID: Int64 = 0
        var processed = 0
        while true {
            try Task.checkCancellation()
            let batch = try await store.pendingMetadata(afterID: afterID, limit: batchSize)
            guard let last = batch.last else { break }
            afterID = last.id
            let extractor = extractor
            let updates = await withTaskGroup(of: MetadataUpdate.self) { group in
                var results: [MetadataUpdate] = []
                var next = batch.makeIterator()
                let pause = pause
                for _ in 0 ..< concurrency {
                    guard let item = next.next() else { break }
                    group.addTask(priority: .utility) {
                        await pause.waitWhileHeld()
                        return await extractor.extract(item)
                    }
                }
                for await update in group {
                    results.append(update)
                    if let item = next.next(), !Task.isCancelled {
                        group.addTask(priority: .utility) {
                            await pause.waitWhileHeld()
                            return await extractor.extract(item)
                        }
                    }
                }
                return results
            }
            try await store.saveMetadata(updates)
            processed += updates.count
        }
        return processed
    }

    // MARK: Watching

    /// Watches a root until the calling task is cancelled, rescanning changed directories.
    ///
    /// Resumes from the stored event id when the FSEvents database is unchanged (catching changes made
    /// while the app was closed); otherwise runs a full diff-scan first.
    public func watch(
        rootID: Int64, onUpdate: @escaping @Sendable (WatchUpdate) -> Void = { _ in },
        progress: (@Sendable (ScanProgress) -> Void)? = nil
    ) async throws {
        let root = try await store.root(id: rootID)
        let databaseUUID = FolderWatcher.eventDatabaseUUID(forPath: root.path)
        var since: UInt64
        if let last = root.lastEventID, databaseUUID != nil, root.eventDatabaseUUID == databaseUUID {
            since = last
        } else {
            since = FolderWatcher.currentEventID()
            let report = try await scan(rootID: rootID, progress: progress)
            try await store.updateEventState(rootID: rootID, lastEventID: since, eventDatabaseUUID: databaseUUID)
            onUpdate(WatchUpdate(events: [], targets: [RescanTarget(relativePath: "", recursive: true)], report: report))
        }
        for await events in watcher.events(at: root.path, since: since) {
            try Task.checkCancellation()
            let targets = ChangePlanner.plan(events, rootPath: root.path)
            var report = ScanReport()
            for target in targets {
                report = try await merge(report, rescan(root: root, target: target))
            }
            if let newest = events.map(\.id).filter({ $0 != 0 }).max(), newest > since {
                since = newest
                try await store.updateEventState(rootID: rootID, lastEventID: newest, eventDatabaseUUID: databaseUUID)
            }
            onUpdate(WatchUpdate(events: events, targets: targets, report: report))
        }
    }

    private func rescan(root: RootFolder, target: RescanTarget) async throws -> ScanReport {
        guard root.isRecursive || target.relativePath.isEmpty else { return ScanReport() }
        // A vanished directory is handled by rescanning its nearest existing ancestor, which tombstones it.
        var relativePath = target.relativePath
        var recursive = target.recursive && root.isRecursive
        while !relativePath.isEmpty, !directoryExists(Self.url(root: root, relativePath: relativePath)) {
            relativePath = (relativePath as NSString).deletingLastPathComponent
            recursive = false
        }
        guard directoryExists(root.url), !isInsidePackage(root: root, relativePath: relativePath) else {
            return ScanReport()
        }
        return try await scan(root: root, relativePath: relativePath, recursive: recursive)
    }

    private func merge(_ lhs: ScanReport, _ rhs: ScanReport) -> ScanReport {
        var total = lhs
        total.directories += rhs.directories
        total.added += rhs.added
        total.updated += rhs.updated
        total.moved += rhs.moved
        total.revived += rhs.revived
        total.missing += rhs.missing
        total.unchanged += rhs.unchanged
        total.unreadableDirectories += rhs.unreadableDirectories
        total.duration += rhs.duration
        return total
    }

    // MARK: Helpers

    static func url(root: RootFolder, relativePath: String) -> URL {
        relativePath.isEmpty ? root.url : root.url.appendingPathComponent(relativePath, isDirectory: true)
    }

    private func directoryExists(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory) && isDirectory.boolValue
    }

    private func isInsidePackage(root: RootFolder, relativePath: String) -> Bool {
        var url = root.url
        for component in relativePath.split(separator: "/") {
            url.appendPathComponent(String(component), isDirectory: true)
            if (try? url.resourceValues(forKeys: [.isPackageKey]))?.isPackage == true {
                return true
            }
        }
        return false
    }
}
