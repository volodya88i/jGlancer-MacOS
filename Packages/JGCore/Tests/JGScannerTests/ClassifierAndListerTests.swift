import Foundation
import JGModel
import JGTestSupport
import Testing
@testable import JGScanner

struct ClassifierAndListerTests {
    @Test(arguments: [
        ("a.jpg", MediaKind.photo), ("B.JPG", .photo), ("c.heic", .photo), ("d.png", .photo), ("e.dng", .photo),
        ("f.mov", .video), ("g.mp4", .video), ("h.m4v", .video), ("i.mkv", .video), ("j.webm", .video),
        ("k.m4a", .audio), ("l.mp3", .audio), ("m.wav", .audio), ("n.flac", .audio), ("o.ogg", .audio),
    ])
    func mediaFilesAreClassified(name: String, kind: MediaKind) {
        #expect(MediaClassifier().classify(fileName: name)?.kind == kind)
    }

    @Test(arguments: ["notes.txt", "doc.pdf", "no_extension", ".jpg", "archive.zip", "page.html"])
    func otherFilesAreIgnored(name: String) {
        #expect(MediaClassifier().classify(fileName: name) == nil)
    }

    @Test func listerSkipsHiddenPackagesSymlinksAndNonMedia() throws {
        let folder = try TemporaryDirectory()
        try folder.write("a.jpg")
        try folder.write("b.txt")
        try folder.write(".hidden.jpg")
        try folder.write(".hidden_dir/c.jpg")
        try folder.write("Bundle.bundle/d.jpg")
        try folder.write("sub/e.jpg")
        try FileManager.default.createSymbolicLink(
            at: folder.url.appendingPathComponent("link.jpg"), withDestinationURL: folder.url.appendingPathComponent("a.jpg")
        )
        try FileManager.default.createSymbolicLink(
            at: folder.url.appendingPathComponent("loop"), withDestinationURL: folder.url
        )
        let listing = try DirectoryLister().list(folder.url, rootID: 1, relativePath: "")
        #expect(listing.files.map(\.name) == ["a.jpg"])
        #expect(listing.subdirectories == ["sub"])
        let file = try #require(listing.files.first)
        #expect(file.size == 1)
        #expect(file.inode != nil)
        #expect(file.typeIdentifier == "public.jpeg")
    }
}

struct FolderListingTests {
    @Test func listsOnlyRequestedKindsInNaturalOrder() throws {
        let folder = try TemporaryDirectory()
        for name in ["IMG_10.jpg", "IMG_2.heic", "img_1.PNG", "clip.mov", ".hidden.jpg", "notes.txt", "sub/deep.jpg"] {
            try folder.write(name)
        }
        let photos = try FolderListing.files(in: folder.url, kinds: [.photo]).map(\.name)
        #expect(photos == ["img_1.PNG", "IMG_2.heic", "IMG_10.jpg"])
        let all = try FolderListing.files(in: folder.url, kinds: Set(MediaKind.allCases)).map(\.name)
        #expect(all == ["clip.mov", "img_1.PNG", "IMG_2.heic", "IMG_10.jpg"])
    }
}
