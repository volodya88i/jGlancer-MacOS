import Foundation
import ImageIO
import JGTestSupport
import Testing
@testable import JGScanner

struct MediaDetailsTests {
    @Test func photoCameraExposureAndLocation() async throws {
        let folder = try TemporaryDirectory()
        let url = folder.url.appendingPathComponent("camera.jpg")
        try MediaFactory.jpeg(at: url, width: 64, height: 48, extra: [
            kCGImagePropertyTIFFDictionary: [kCGImagePropertyTIFFMake: "Apple", kCGImagePropertyTIFFModel: "iPhone 15 Pro"],
            kCGImagePropertyExifDictionary: [
                kCGImagePropertyExifFNumber: 1.8, kCGImagePropertyExifExposureTime: 0.008,
                kCGImagePropertyExifISOSpeedRatings: [125], kCGImagePropertyExifFocalLength: 6.86,
                kCGImagePropertyExifLensModel: "iPhone 15 Pro back camera",
            ],
            kCGImagePropertyGPSDictionary: [
                kCGImagePropertyGPSLatitude: 55.75, kCGImagePropertyGPSLatitudeRef: "N",
                kCGImagePropertyGPSLongitude: 37.62, kCGImagePropertyGPSLongitudeRef: "E",
            ],
        ])
        let details = await MediaDetails.read(url, kind: .photo)
        #expect(details.camera == "Apple iPhone 15 Pro")
        #expect(details.aperture == 1.8)
        #expect(details.exposureTime == 0.008)
        #expect(details.iso == 125)
        #expect(details.lens == "iPhone 15 Pro back camera")
        #expect(abs((details.latitude ?? 0) - 55.75) < 0.001 && abs((details.longitude ?? 0) - 37.62) < 0.001)
    }

    @Test func cameraNamesDoNotRepeatTheMaker() {
        #expect(MediaDetails.cameraName(make: "Canon", model: "Canon EOS R5") == "Canon EOS R5")
        #expect(MediaDetails.cameraName(make: "NIKON CORPORATION", model: "NIKON Z 6") == "NIKON Z 6")
        #expect(MediaDetails.cameraName(make: "Apple", model: nil) == "Apple")
        #expect(MediaDetails.cameraName(make: nil, model: nil) == nil)
    }

    @Test func audioCodecRateAndChannels() async throws {
        let folder = try TemporaryDirectory()
        let url = folder.url.appendingPathComponent("tone.wav")
        try MediaFactory.wav(at: url, seconds: 0.5)
        let details = await MediaDetails.read(url, kind: .audio)
        #expect(details.audioCodec == "PCM")
        #expect((details.sampleRate ?? 0) > 0)
        #expect((details.channels ?? 0) >= 1)
        #expect(details.videoCodec == nil)
    }

    @Test func videoCodecAndFrameRate() async throws {
        let folder = try TemporaryDirectory()
        let url = folder.url.appendingPathComponent("clip.mov")
        try await MediaFactory.mov(at: url, width: 64, height: 48, frames: 10, fps: 25)
        let details = await MediaDetails.read(url, kind: .video)
        #expect(details.videoCodec != nil)
        #expect(abs((details.frameRate ?? 0) - 25) < 1)
    }
}
