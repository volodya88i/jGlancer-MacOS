import CoreGraphics
import Foundation
import Testing
@testable import JGModel

struct SizeMapTests {
    /// Music ▸ Album (Disc), Music ▸ Empty.
    private let folders: FolderNode = {
        func folder(_ id: Int64, _ name: String, parent: Int64?) -> Folder {
            Folder(id: id, rootID: 1, parentID: parent, relativePath: name, name: name, state: .present)
        }
        let disc = FolderNode(folder: folder(3, "Disc", parent: 2), children: nil)
        let album = FolderNode(folder: folder(2, "Album", parent: 1), children: [disc])
        let empty = FolderNode(folder: folder(4, "Empty", parent: 1), children: nil)
        return FolderNode(folder: folder(1, "Music", parent: nil), children: [album, empty])
    }()

    private let files = [
        SizeEntry(id: 10, folderID: 1, size: 100, kind: .audio, name: "intro.WAV"),
        SizeEntry(id: 11, folderID: 2, size: 300, kind: .audio, name: "a.mp3"),
        SizeEntry(id: 12, folderID: 3, size: 600, kind: .photo, name: "b.jpg"),
        SizeEntry(id: 13, folderID: 3, size: 0, kind: .photo, name: "zero.jpg"),
    ]

    @Test func foldersSumTheirFilesLargestFirstAndEmptyOnesGo() throws {
        let tree = SizeTree(folder: folders, files: files)
        let root = try #require(tree.root)
        #expect(root.item == .folder(1) && root.size == 1000)
        // Album (900) before intro.WAV (100); Empty holds nothing and is no node; a 0-byte file is no node either.
        #expect(root.children.map { tree.nodes[$0].item } == [.folder(2), .file(10)])
        let album = tree.nodes[root.children[0]]
        #expect(album.size == 900)
        #expect(album.children.map { tree.nodes[$0].item } == [.folder(3), .file(11)])
        #expect(tree.nodes.count == 6)
        #expect(tree.nodes[root.children[1]].fileExtension == "wav")
        #expect(SizeTree(folder: folders, files: []).isEmpty)
    }

    @Test func squarifiedRectanglesFillTheRectInProportionWithoutOverlap() {
        let bounds = CGRect(x: 10, y: 20, width: 600, height: 400)
        let values: [Double] = [500, 300, 200, 120, 80, 50, 30, 20]
        let rects = SizeMapLayout.squarify(values, in: bounds)
        let total = values.reduce(0, +)
        for (value, rect) in zip(values, rects) {
            let expected = Double(bounds.width * bounds.height) * value / total
            #expect(abs(Double(rect.width * rect.height) - expected) < 0.01 * expected)
            #expect(bounds.insetBy(dx: -0.01, dy: -0.01).contains(rect))
            // Squarified: no sliver thinner than a tenth of its length.
            #expect(min(rect.width, rect.height) / max(rect.width, rect.height) > 0.1)
        }
        for (first, rect) in rects.enumerated() {
            for other in rects[(first + 1)...] {
                let overlap = rect.intersection(other)
                #expect(overlap.isNull || overlap.width * overlap.height < 0.01)
            }
        }
        #expect(SizeMapLayout.squarify([0, 0], in: bounds) == [.zero, .zero])
    }

    @Test func theLayoutNestsFoldersUnderTheirNameBandAndFindsTheFileUnderThePointer() throws {
        let tree = SizeTree(folder: folders, files: files)
        let layout = SizeMapLayout(tree, in: CGRect(x: 0, y: 0, width: 800, height: 500), header: 16, padding: 2, minSide: 4)
        let root = try #require(layout.rects[0])
        #expect(root == CGRect(x: 0, y: 0, width: 800, height: 500))
        #expect(layout.boxes.first?.header == CGRect(x: 0, y: 0, width: 800, height: 16))
        for (index, node) in tree.nodes.enumerated() {
            for child in node.children {
                let outer = try #require(layout.rects[index])
                let inner = try #require(layout.rects[child])
                #expect(outer.insetBy(dx: -0.01, dy: -0.01).contains(inner))
            }
        }
        let photo = try #require(tree.nodes.firstIndex { $0.item == .file(12) })
        let rect = try #require(layout.rects[photo])
        #expect(layout.hit(CGPoint(x: rect.midX, y: rect.midY), in: tree) == photo)
        #expect(layout.hit(CGPoint(x: 900, y: 10), in: tree) == nil)
    }

    @Test func aModuleShownWhereTheOtherIsTakesTheFreePlaceAndMovingSwaps() {
        var state = LibraryViewState()
        #expect(state.slot(of: .preview) == .right && state.slot(of: .sizeMap) == nil)
        state.setVisible(.sizeMap, true)
        #expect(state.slot(of: .sizeMap) == .bottom)
        state.move(.sizeMap)
        #expect(state.slot(of: .sizeMap) == .right && state.slot(of: .preview) == .bottom)
        state.move(.sizeMap)
        #expect(state.slot(of: .sizeMap) == .bottom && state.slot(of: .preview) == .right)
        // Alone, a module just moves; shown again where the other is, it goes to the free place.
        state.setVisible(.preview, false)
        state.move(.sizeMap)
        #expect(state.slot(of: .sizeMap) == .right)
        state.setVisible(.preview, true)
        #expect(state.slot(of: .preview) == .bottom && state.module(in: .right) == .sizeMap)
    }
}
