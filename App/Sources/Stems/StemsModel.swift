import Foundation
import JGStems
import Observation

/// Split into Stems in the app (D-97): the window's request and remembered choice, model downloads, and the queue of
/// songs, split one at a time in the background with progress and Stop.
@MainActor
@Observable
final class StemsModel {
    /// The split window for these songs.
    struct Request: Identifiable {
        let id = UUID()
        let songs: [URL]
    }

    /// A song being split.
    struct Running {
        let job: StemJob
        var progress = 0.0
        let started = Date()
    }

    var request: Request?
    /// Mode and ticks, remembered between uses (not the folder).
    var choice: StemChoice {
        didSet { save() }
    }

    /// Compact or Full, remembered (Settings → Library → Stem Splitting; D-103).
    var usesFullModel: Bool {
        didSet {
            if isPersistent {
                UserDefaults.standard.set(usesFullModel, forKey: Self.fullModelKey)
            }
        }
    }

    /// Bytes received per model being downloaded, by name.
    private(set) var downloads: [String: Int64] = [:]
    private(set) var downloadError: String?
    private(set) var running: Running?
    private(set) var waiting: [StemJob] = []
    /// Bumped when a model is installed or removed (Settings lists them).
    private(set) var modelsVersion = 0

    let store: StemModelStore
    /// A finished song: its files (the app shows a toast and registers the undo).
    @ObservationIgnored var onDone: ((StemJob, [URL]) -> Void)?
    @ObservationIgnored var onFailed: ((StemJob, Error) -> Void)?
    @ObservationIgnored private var downloadTasks: [String: Task<Void, Never>] = [:]
    @ObservationIgnored private var runTask: Task<Void, Never>?
    @ObservationIgnored private let stopFlag = StopFlag()
    @ObservationIgnored private let isPersistent: Bool
    private static let choiceKey = "StemChoice"
    private static let fullModelKey = "StemFullModel"

    init(store: StemModelStore, isPersistent: Bool) {
        self.store = store
        self.isPersistent = isPersistent
        let saved = isPersistent ? UserDefaults.standard.data(forKey: Self.choiceKey) : nil
        choice = saved.flatMap { try? JSONDecoder().decode(StemChoice.self, from: $0) } ?? StemChoice()
        // Full by default: quality over the size of the download.
        usesFullModel = isPersistent ? UserDefaults.standard.object(forKey: Self.fullModelKey) as? Bool ?? true : true
    }

    private func save() {
        guard isPersistent, let data = try? JSONEncoder().encode(choice) else { return }
        UserDefaults.standard.set(data, forKey: Self.choiceKey)
    }

    // MARK: Models

    /// The model a split with the window's choice takes now.
    var chosenModel: StemModelInfo {
        StemModelInfo.model(for: choice.network, full: usesFullModel)
    }

    func isInstalled(_ model: StemModelInfo) -> Bool {
        _ = modelsVersion
        return store.isInstalled(model)
    }

    /// Downloads a model (only ever on the user's click).
    func download(_ model: StemModelInfo) {
        guard downloadTasks[model.name] == nil else { return }
        downloadError = nil
        downloads[model.name] = 0
        let store = store
        downloadTasks[model.name] = Task { [weak self] in
            do {
                try await store.download(model) { received in
                    Task { @MainActor in
                        if self?.downloads[model.name] != nil {
                            self?.downloads[model.name] = received
                        }
                    }
                }
                self?.downloadFinished(model, error: nil)
            } catch {
                self?.downloadFinished(model, error: error)
            }
        }
    }

    func stopDownload(_ model: StemModelInfo) {
        downloadTasks[model.name]?.cancel()
    }

    private func downloadFinished(_ model: StemModelInfo, error: Error?) {
        downloadTasks[model.name] = nil
        downloads[model.name] = nil
        modelsVersion += 1
        guard let error, !(error is CancellationError), (error as? URLError)?.code != .cancelled else { return }
        downloadError = error is StemModelError
            ? String(localized: "The download was damaged. Try again.", comment: "Stem model download: checksum mismatch")
            : String(
                localized: "The model could not be downloaded. Check the connection and try again.",
                comment: "Stem model download failed"
            )
    }

    func remove(_ model: StemModelInfo) {
        try? store.remove(model)
        modelsVersion += 1
    }

    // MARK: Splitting

    /// Queues the songs with the current choice: each into a new "<song> split" folder next to it, or inside
    /// `folder` when one was chosen.
    func split(_ songs: [URL], into folder: URL?) {
        let model = chosenModel
        for song in songs {
            let target: URL
            if let folder, songs.count == 1 {
                target = folder
            } else {
                let parent = folder ?? song.deletingLastPathComponent()
                target = StemNaming.defaultFolder(for: parent.appendingPathComponent(song.lastPathComponent)) {
                    FileManager.default.fileExists(atPath: $0.path)
                }
            }
            let makesFolder = !FileManager.default.fileExists(atPath: target.path)
            waiting.append(StemJob(song: song, model: model, stems: choice.stems, folder: target, makesFolder: makesFolder))
        }
        startNext()
    }

    /// Stops the song being split and drops the ones waiting.
    func stop() {
        waiting.removeAll()
        stopFlag.set(true)
    }

    private func startNext() {
        guard running == nil, !waiting.isEmpty else { return }
        let job = waiting.removeFirst()
        running = Running(job: job)
        stopFlag.set(false)
        let compiled = store.compiledURL(job.model)
        let flag = stopFlag
        runTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) { () -> Result<[URL], Error> in
                Result {
                    try StemJobRunner.run(job, compiledModel: compiled, progress: { share in
                        Task { @MainActor in self?.running?.progress = share }
                    }, isCancelled: { flag.get() })
                }
            }.value
            self?.finished(job, result)
        }
    }

    private func finished(_ job: StemJob, _ result: Result<[URL], Error>) {
        running = nil
        runTask = nil
        switch result {
        case let .success(files):
            onDone?(job, files)
        case let .failure(error):
            if !(error is StemSplitCancelled) {
                onFailed?(job, error)
            }
        }
        startNext()
    }

    /// Seconds left for the song being split, from its pace so far.
    var secondsLeft: Double? {
        guard let running, running.progress > 0.05 else { return nil }
        let spent = Date().timeIntervalSince(running.started)
        return spent / running.progress * (1 - running.progress)
    }
}

/// A flag the background split reads between pieces.
final class StopFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false

    func get() -> Bool {
        lock.withLock { value }
    }

    func set(_ newValue: Bool) {
        lock.withLock { value = newValue }
    }
}
