import Foundation
import JGModel
import JGPlayback
import JGStore

/// Tempo and key of songs (D-106): remembered in the library's database by path, size and modification date, found
/// on request. Without a library they are remembered for this run only.
actor AudioAnalyses {
    private var store: LibraryStore?
    private var memory: [Version: AudioAnalysis] = [:]

    private struct Version: Hashable {
        let path: String
        let size: Int64
        let modifiedAt: Date
    }

    func setStore(_ store: LibraryStore?) {
        self.store = store
    }

    /// What was found earlier in this version of the file, or nil.
    func known(_ url: URL) async -> AudioAnalysis? {
        guard let version = Self.version(of: url) else { return nil }
        if let found = memory[version] {
            return found
        }
        return try? await store?.audioAnalysis(path: version.path, size: version.size, modifiedAt: version.modifiedAt)
    }

    /// Decodes and analyzes the file and keeps the result; nil when it has no usable audio or nothing was found.
    func analyze(_ url: URL) async -> AudioAnalysis? {
        let found = await Task.detached(priority: .userInitiated) { await AudioAnalyzer.analyze(url) }.value
        guard let found, let version = Self.version(of: url) else { return nil }
        memory[version] = found
        try? await store?.saveAudioAnalysis(found, path: version.path, size: version.size, modifiedAt: version.modifiedAt)
        await MainActor.run { NotificationCenter.default.post(name: .audioAnalysisFound, object: url) }
        return found
    }

    private static func version(of url: URL) -> Version? {
        guard let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
              let size = values.fileSize, let modifiedAt = values.contentModificationDate
        else { return nil }
        return Version(path: url.standardizedFileURL.path, size: Int64(size), modifiedAt: modifiedAt)
    }
}
