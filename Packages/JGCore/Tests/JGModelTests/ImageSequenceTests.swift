import Testing
@testable import JGModel

struct ImageSequenceTests {
    private func members(_ names: [String], folder: Int64 = 1, firstID: Int64 = 1) -> [ImageSequences.Member] {
        names.enumerated().map { ImageSequences.Member(id: firstID + Int64($0.offset), folderID: folder, name: $0.element) }
    }

    @Test func fiveConsecutiveFramesFold() {
        let found = ImageSequences.find(in: members((1 ... 5).map { String(format: "render_%03d.png", $0) }))
        #expect(found == [ImageSequence(frames: [1, 2, 3, 4, 5])])
        #expect(found.first?.head == 1)
        #expect(ImageSequences.find(in: members((1 ... 4).map { "render_\($0).png" })).isEmpty) // four are not enough
    }

    @Test func aGapStartsANewRun() {
        let names = (1 ... 6).map { "f\($0).png" } + (8 ... 12).map { "f\($0).png" } + (20 ... 22).map { "f\($0).png" }
        let found = ImageSequences.find(in: members(names))
        #expect(found.map(\.frames.count) == [6, 5])
    }

    @Test func prefixExtensionAndFolderMustMatch() {
        var all = members((1 ... 5).map { "a_\($0).png" })
        all += members((6 ... 9).map { "a_\($0).jpg" }, firstID: 100) // other extension: only four
        all += members((11 ... 12).map { "a_\($0).png" }, folder: 2, firstID: 200) // other folder
        let found = ImageSequences.find(in: all)
        #expect(found == [ImageSequence(frames: [1, 2, 3, 4, 5])])
    }

    @Test func cameraNamesNeverFold() {
        for prefix in ["IMG_", "DSC", "PXL_", "Screenshot ", "GOPR"] {
            #expect(ImageSequences.find(in: members((1 ... 9).map { "\(prefix)\($0).JPG" })).isEmpty, "\(prefix)")
        }
        #expect(ImageSequences.find(in: members((1 ... 9).map { "Image\($0).png" })).isEmpty)
    }

    @Test func framesComeInNumberOrder() {
        let names = ["s5.png", "s3.png", "s1.png", "s4.png", "s2.png"]
        #expect(ImageSequences.find(in: members(names)).first?.frames == [3, 5, 2, 4, 1])
    }
}
