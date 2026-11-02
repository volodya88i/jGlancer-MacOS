import Testing
@testable import JGModel

struct MediaKindTests {
    @Test func rawValuesMatchDatabaseContract() {
        #expect(MediaKind.photo.rawValue == 0)
        #expect(MediaKind.video.rawValue == 1)
        #expect(MediaKind.audio.rawValue == 2)
        #expect(MediaKind.allCases == [.photo, .video, .audio])
    }
}
