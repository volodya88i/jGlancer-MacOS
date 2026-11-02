import Foundation
import JGModel
import JGScanner
import JGStore
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
    @ObservationIgnored private var lastProgress: [Int64: Date] = [:]
    static let progressInterval = 0.25

    private let scanner: LibraryScanner
    private var watchTasks: [Int64: Task<Void, Never>] = [:]
    private var indexingRoots: Set<Int64> = []
    private var metadataTask: Task<Void, Never>?
    private var metadataRequested = false

    /// The photo viewer holds it while decoding: metadata reading waits (D-82).
    var pause: PauseGate {
        scanner.pause
    }

    init(scanner: LibraryScanner) {
        self.scanner = scanner
    }

    /// Watches a root; `isNew` (added in this session) reports its first scan's progress.
    func startWatching(_ root: RootFolder, isNew: Bool = false) {
        let rootID = root.id
        let scanner = scanner
        indexingRoots.insert(rootID)
        if isNew {
            adding[rootID] = ScanProgress()
        }
        updateActivity()
        let progress = isNew ? progressReporter(for: rootID) : nil
        let onUpdate: @Sendable (WatchUpdate) -> Void = { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.rootIndexed(rootID, isOnline: true) }
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
        watchTasks[rootID]?.cancel()
        watchTasks[rootID] = nil
        indexingRoots.remove(rootID)
        adding[rootID] = nil
        updateActivity()
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
