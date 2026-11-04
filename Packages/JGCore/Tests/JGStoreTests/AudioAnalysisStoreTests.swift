import Foundation
import JGModel
import Testing
@testable import JGStore

struct AudioAnalysisStoreTests {
    @Test func analysisHoldsWhileTheFileIsUnchanged() async throws {
        let store = try LibraryStore.inMemory()
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let found = AudioAnalysis(bpm: 127.9, key: MusicKey(tonic: 9, isMinor: true))
        try await store.saveAudioAnalysis(found, path: "/music/song.flac", size: 1000, modifiedAt: date)
        #expect(try await store.audioAnalysis(path: "/music/song.flac", size: 1000, modifiedAt: date) == found)
        #expect(try await store.audioAnalysis(path: "/music/song.flac", size: 1001, modifiedAt: date) == nil)
        #expect(try await store.audioAnalysis(path: "/music/song.flac", size: 1000, modifiedAt: date + 1) == nil)
        // A tempo without a key, replacing the earlier row.
        let tempoOnly = AudioAnalysis(bpm: 90, key: nil)
        try await store.saveAudioAnalysis(tempoOnly, path: "/music/song.flac", size: 1000, modifiedAt: date)
        #expect(try await store.audioAnalysis(path: "/music/song.flac", size: 1000, modifiedAt: date) == tempoOnly)
    }
}
