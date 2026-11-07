import Foundation
import Testing
@testable import JGModel

struct ListOutlineTests {
    /// Music ▸ Album A ▸ Disc 2, Music ▸ Album B, Music ▸ Empty (no files of the query).
    private let tree: FolderNode = {
        func folder(_ id: Int64, _ name: String, parent: Int64?) -> Folder {
            Folder(id: id, rootID: 1, parentID: parent, relativePath: name, name: name, state: .present)
        }
        let disc = FolderNode(folder: folder(4, "Disc 2", parent: 2), children: nil)
        let albumA = FolderNode(folder: folder(2, "Album A", parent: 1), children: [disc])
        let albumB = FolderNode(folder: folder(3, "Album B", parent: 1), children: nil)
        let empty = FolderNode(folder: folder(5, "Empty", parent: 1), children: nil)
        return FolderNode(folder: folder(1, "Music", parent: nil), children: [albumA, albumB, empty])
    }()

    private let refs = [
        AssetRef(id: 10, kind: .audio, folderID: 1),
        AssetRef(id: 11, kind: .audio, folderID: 2),
        AssetRef(id: 12, kind: .audio, folderID: 4),
        AssetRef(id: 13, kind: .audio, folderID: 3),
        AssetRef(id: 14, kind: .audio, folderID: 2),
    ]

    @Test func foldersComeFirstAndHoldTheirFilesInTheQueryOrder() {
        let outline = ListOutline(refs: refs, shown: tree)
        #expect(outline.children(of: nil) == [.folder(2), .folder(3), .asset(10)])
        #expect(outline.children(of: 2) == [.folder(4), .asset(11), .asset(14)])
        #expect(outline.children(of: 4) == [.asset(12)])
        #expect(outline.children(of: 3) == [.asset(13)])
        // A folder without files of the query is no row.
        #expect(outline.folders[5] == nil)
        #expect(outline.folders[2]?.name == "Album A")
    }

    @Test func aDescendingSortReversesTheFolders() {
        let outline = ListOutline(refs: refs, shown: tree, foldersDescending: true)
        #expect(outline.children(of: nil) == [.folder(3), .folder(2), .asset(10)])
    }

    @Test func theFolderPathLeadsToANestedFile() {
        let outline = ListOutline(refs: refs, shown: tree)
        #expect(outline.folderPath(toAsset: 12) == [2, 4])
        #expect(outline.folderPath(toAsset: 13) == [3])
        #expect(outline.folderPath(toAsset: 10).isEmpty)
    }

    @Test func withoutSubfoldersOrATreeTheListIsFlat() {
        // Subfolders off: the query holds the folder's own files only.
        let own = ListOutline(refs: [refs[0]], shown: tree)
        #expect(own.children(of: nil) == [.asset(10)])
        #expect(own.folders.isEmpty)
        // An album or a search of the whole library: no tree.
        let flat = ListOutline(refs: refs, shown: nil)
        #expect(flat.children(of: nil) == refs.map { .asset($0.id) })
    }

    @Test func aFileInAFolderTheTreeDoesNotKnowStaysOnTop() {
        let outline = ListOutline(refs: [AssetRef(id: 20, kind: .photo, folderID: 99)], shown: tree)
        #expect(outline.children(of: nil) == [.asset(20)])
    }

    @Test func theViewModeIsRestoredAndOldStatesDefaultToTheGrid() throws {
        var state = LibraryViewState()
        state.viewMode = .list
        state.listRowHeight = 40
        let decoded = try JSONDecoder().decode(LibraryViewState.self, from: JSONEncoder().encode(state))
        #expect(decoded.viewMode == .list && decoded.listRowHeight == 40)
        let old = try JSONDecoder().decode(LibraryViewState.self, from: Data("{\"tileSide\": 200}".utf8))
        #expect(old.viewMode == .grid && old.tileSide == 200)
    }
}
