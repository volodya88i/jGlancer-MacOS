import Foundation
import JGTestSupport
import Testing
@testable import JGStems

/// The published models download, pass their checksums and compile (developer runs only: `JG_STEM_DOWNLOAD=1`;
/// `JG_STEM_DOWNLOAD=roformer` also downloads the 423 MB RoFormer one).
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

    private static let download = ProcessInfo.processInfo.environment["JG_STEM_DOWNLOAD"]

    @Test(.enabled(if: download == "roformer")) func theRoFormerModelDownloads() async throws {
        let folder = try TemporaryDirectory()
        let store = StemModelStore(folder: folder.url)
        try await store.download(.roformerCompact) { _ in }
        #expect(store.isInstalled(.roformerCompact))
        print("\(StemModelInfo.roformerCompact.name): installed \(store.installedBytes(.roformerCompact)) bytes")
    }
}
