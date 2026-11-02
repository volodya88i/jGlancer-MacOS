import Foundation
import JGTestSupport
import Testing
@testable import JGStems

/// The published model downloads, passes its checksum and compiles (developer runs only: `JG_STEM_DOWNLOAD=1`).
struct StemDownloadTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["JG_STEM_DOWNLOAD"] != nil)) func theSmallerModelsDownload() async throws {
        let folder = try TemporaryDirectory()
        let store = StemModelStore(folder: folder.url)
        for model in [StemModelInfo.six, .fourCompact, .sixCompact] {
            try await store.download(model) { _ in }
            #expect(store.isInstalled(model))
            print("\(model.name): installed \(store.installedBytes(model)) bytes")
        }
    }
}
