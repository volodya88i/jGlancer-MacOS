import AppKit
import Foundation
import JGModel
import JGScanner
import Observation

/// Keeps the library in sync in the background: one FSEvents watch per root (which also runs the first
/// scan) and stage-2 metadata extraction after every change (docs/ARCHITECTURE.md §5).
@MainActor
@Observable
final class LibraryIndexer {
    /// Background work shown in the status bar.
    enum Activity: Equatable {
        case indexing
        case readingDetails
    }

    private(set) var activity: Activity?
    /// Roots whose folder is unavailable (unmounted volume, moved or deleted).
    private(set) var offlineRoots: Set<Int64> = []
    /// Folders added in this session whose first scan is running, with what it found so far (published at most
    /// four times a second); they stay out of the sidebar meanwhile (D-85).
    private(set) var adding: [Int64: ScanProgress] = [:]
    /// A watched root's files changed on disk (added, edited elsewhere, downloaded from the cloud): views drop their
    /// cached rows (set by the library model).
    @ObservationIgnored var onFilesChanged: (() -> Void)?
    @ObservationIgnored private var lastProgress: [Int64: Date] = [:]
    static let progressInterval = 0.25

    private let scanner: LibraryScanner
    private var watchTasks: [Int64: Task<Void, Never>] = [:]
    /// Every root being watched, online or not, so a disk plugged in again brings its roots back.
    @ObservationIgnored private var watchedRoots: [Int64: RootFolder] = [:]
    @ObservationIgnored private var volumeObservers: [NSObjectProtocol] = []
    private var indexingRoots: Set<Int64> = []
    private var metadataTask: Task<Void, Never>?
    private var metadataRequested = false

    /// The photo viewer holds it while decoding: metadata reading waits (D-82).
    var pause: PauseGate {
        scanner.pause
    }

    init(scanner: LibraryScanner) {
        self.scanner = scanner
        observeVolumes()
    }

    /// Watches a root; `isNew` (added in this session) reports its first scan's progress.
    func startWatching(_ root: RootFolder, isNew: Bool = false) {
        let rootID = root.id
        let scanner = scanner
        watchedRoots[rootID] = root
        indexingRoots.insert(rootID)
        if isNew {
            adding[rootID] = ScanProgress()
        }
        updateActivity()
        let progress = isNew ? progressReporter(for: rootID) : nil
        let onUpdate: @Sendable (WatchUpdate) -> Void = { [weak self] update in
            guard let self else { return }
            let changed = update.report.hasChanges
            Task { @MainActor in
                self.rootIndexed(rootID, isOnline: true)
                if changed {
                    self.onFilesChanged?()
                }
            }
        }
        watchTasks[rootID] = Task { [weak self] in
            do {
                try await scanner.watch(rootID: rootID, onUpdate: onUpdate, progress: progress)
            } catch is CancellationError {
                return
            } catch {
                self?.rootIndexed(rootID, isOnline: false)
            }
        }
    }

    func stopWatching(_ rootID: Int64) {
        watchedRoots[rootID] = nil
        offlineRoots.remove(rootID)
        endWatch(rootID)
    }

    private func endWatch(_ rootID: Int64) {
        watchTasks[rootID]?.cancel()
        watchTasks[rootID] = nil
        indexingRoots.remove(rootID)
        adding[rootID] = nil
        updateActivity()
    }

    // MARK: Disks

    /// Disks plugged in or ejected while the app runs (D-124): a root that comes back is watched again (its changes
    /// meanwhile are caught up from FSEvents' history, or by a diff-scan); a root that goes away goes offline at once,
    /// with its watch stopped, instead of looking online behind an FSEvents stream that no longer reports anything.
    private func observeVolumes() {
        let center = NSWorkspace.shared.notificationCenter
        volumeObservers = [NSWorkspace.didMountNotification, NSWorkspace.didUnmountNotification].map { name in
            center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.volumesChanged() }
            }
        }
    }

    private func volumesChanged() {
        for (rootID, root) in watchedRoots {
            var isDirectory: ObjCBool = false
            let isAvailable = FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) && isDirectory.boolValue
            if isAvailable, offlineRoots.contains(rootID) {
                offlineRoots.remove(rootID)
                startWatching(root)
            } else if !isAvailable, !offlineRoots.contains(rootID) {
                endWatch(rootID)
                offlineRoots.insert(rootID)
            }
        }
    }

    /// A watch update arrived (`isOnline`), or watching failed because the folder is unavailable.
    /// Hands the scanner's progress (from its own thread) to the main actor.
    private func progressReporter(for rootID: Int64) -> @Sendable (ScanProgress) -> Void {
        { [weak self] found in
            Task { @MainActor in
                self?.progressed(rootID, found)
            }
        }
    }

    private func progressed(_ rootID: Int64, _ found: ScanProgress) {
        guard adding[rootID] != nil else { return }
        let now = Date()
        if let last = lastProgress[rootID], now.timeIntervalSince(last) < Self.progressInterval {
            return
        }
        lastProgress[rootID] = now
        adding[rootID] = found
    }

    private func rootIndexed(_ rootID: Int64, isOnline: Bool) {
        // A late report of a watch stopped meanwhile (its disk was ejected) must not bring the root back online.
        guard watchTasks[rootID] != nil else { return }
        indexingRoots.remove(rootID)
        adding[rootID] = nil
        lastProgress[rootID] = nil
        if isOnline {
            offlineRoots.remove(rootID)
            requestMetadata()
        } else {
            offlineRoots.insert(rootID)
        }
        updateActivity()
    }

    /// Runs stage 2 until nothing is pending; requests during a run trigger one more pass.
    private func requestMetadata() {
        metadataRequested = true
        guard metadataTask == nil else { return }
        metadataTask = Task(priority: .utility) { [weak self, scanner] in
            while let self, metadataRequested {
                metadataRequested = false
                _ = try? await scanner.extractMetadata()
            }
            self?.metadataTask = nil
            self?.updateActivity()
        }
        updateActivity()
    }

    private func updateActivity() {
        activity = !indexingRoots.isEmpty ? .indexing : (metadataTask != nil ? .readingDetails : nil)
    }
}
