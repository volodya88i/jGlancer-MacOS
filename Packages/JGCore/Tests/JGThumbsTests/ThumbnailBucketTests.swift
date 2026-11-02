import Testing
@testable import JGThumbs

struct ThumbnailBucketTests {
    @Test func pixelSizesMatchArchitecture() {
        #expect(ThumbnailBucket.allCases.map(\.maxPixelSize) == [160, 320, 640])
        #expect(ThumbnailBucket.allCases.map(\.rawValue) == [0, 1, 2])
    }

    @Test(arguments: [
        (1, ThumbnailBucket.small), (160, .small), (161, .medium),
        (320, .medium), (321, .large), (640, .large), (5000, .large),
    ])
    func coveringPicksSmallestSufficientBucket(pixels: Int, expected: ThumbnailBucket) {
        #expect(ThumbnailBucket.covering(longestSidePixels: pixels) == expected)
    }
}
