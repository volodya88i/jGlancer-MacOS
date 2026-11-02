import AppKit
import JGStems

/// Split into Stems (D-97): the window from a song's menu, and what a finished split leaves (a toast with Show in
/// Finder; ⌘Z moves the stems to the Trash).
extension AppModel {
    func makeStems() -> StemsModel {
        let stems = StemsModel(store: StemModelStore(folder: AppPaths.stemModels), isPersistent: AppPaths.dataOverride == nil)
        stems.onDone = { [weak self] job, files in self?.stemsFinished(job, files) }
        stems.onFailed = { [weak self] job, _ in
            let name = job.song.deletingPathExtension().lastPathComponent
            self?.fileOps?.showMessage(String(
                localized: "“\(name)” could not be split.",
                comment: "Split into Stems failed; the argument is a song"
            ))
        }
        return stems
    }

    /// Split into Stems… on songs: the window.
    func requestStemSplit(_ target: ActionTarget) async {
        let songs = await target.urls().filter { classifier.classify(fileName: $0.lastPathComponent)?.kind == .audio }
        guard !songs.isEmpty else { return }
        stems.request = StemsModel.Request(songs: songs)
    }

    private func stemsFinished(_ job: StemJob, _ files: [URL]) {
        let made = job.makesFolder ? [job.folder] : files
        fileOps?.showMessage(
            String(
                localized: "Split into \(files.count) stems",
                comment: "Toast after Split into Stems; the argument is the number of files"
            ),
            reveal: job.makesFolder ? job.folder : files.first
        )
        fileOps?.register(CustomUndo(name: String(
            localized: "Split into Stems…",
            comment: "Action: separates a song into vocals, drums, bass…"
        )) {
            for url in made {
                try? FileManager.default.trashItem(at: url, resultingItemURL: nil)
            }
            return nil
        })
    }
}
