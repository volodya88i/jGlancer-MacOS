import CoreGraphics
import Foundation
import Testing
@testable import JGModel

struct GridGeometryTests {
    /// 1000 px wide, 160 target, 8 gutter, 16 inset: (968 + 8) / 168 = 5 columns of 187 px.
    private let grid = GridGeometry(itemCount: 23, width: 1000, targetTileSide: 160, gutter: 8, inset: 16, captionHeight: 20)

    @Test func columnsStretchToFillTheRow() {
        #expect(grid.columns == 5)
        #expect(grid.tileSide == 187)
        #expect(grid.rowCount == 5)
        #expect(grid.frame(at: 6) == CGRect(x: 16 + 195, y: 16 + 215, width: 187, height: 207))
        #expect(grid.contentHeight == CGFloat(32 + 5 * 207 + 4 * 8))
    }

    @Test func whileSizingTilesKeepTheTargetSizeCentered() {
        // 5 columns of exactly 160: 5 × 160 + 4 × 8 = 832 of 968, so 68 on each side.
        let live = GridGeometry(itemCount: 23, width: 1000, targetTileSide: 160, gutter: 8, inset: 16, captionHeight: 20, fillsRow: false)
        #expect(live.columns == 5)
        #expect(live.tileSide == 160)
        #expect(live.frame(at: 6) == CGRect(x: 16 + 68 + 168, y: 16 + 188, width: 160, height: 180))
        #expect(live.index(at: CGPoint(x: 20, y: 20)) == nil)
        // A little more and the size grows smoothly, with the same columns.
        let bigger = GridGeometry(itemCount: 23, width: 1000, targetTileSide: 170, gutter: 8, inset: 16, captionHeight: 20, fillsRow: false)
        #expect(bigger.columns == 5)
        #expect(bigger.tileSide == 170)
        #expect(grid.leading == 16)
    }

    @Test func gutterPointsTakeTheNearestTile() {
        let first = grid.frame(at: 0)
        let second = grid.frame(at: 1)
        // Just left and just right of the gutter between the first two tiles.
        #expect(grid.nearestIndex(to: CGPoint(x: first.maxX + 2, y: first.midY)) == 0)
        #expect(grid.nearestIndex(to: CGPoint(x: second.minX - 2, y: first.midY)) == 1)
        // Under the last row, and right of the last tile: the last tile.
        let last = grid.frame(at: 22)
        #expect(grid.nearestIndex(to: CGPoint(x: last.maxX + 300, y: last.midY)) == 22)
        #expect(grid.nearestIndex(to: CGPoint(x: first.minX - 10, y: -50)) == 0)
        #expect(GridGeometry(itemCount: 0, width: 500, targetTileSide: 100, gutter: 8, inset: 16, captionHeight: 0)
            .nearestIndex(to: .zero) == nil)
    }

    @Test func narrowWindowsKeepOneColumn() {
        let narrow = GridGeometry(itemCount: 3, width: 50, targetTileSide: 160, gutter: 8, inset: 16, captionHeight: 0)
        #expect(narrow.columns == 1)
        #expect(narrow.tileSide == 18)
    }

    @Test func visibleRangeCoversWholeRows() {
        #expect(grid.indices(in: CGRect(x: 0, y: 0, width: 1000, height: 100)) == 0 ..< 5)
        #expect(grid.indices(in: CGRect(x: 0, y: 240, width: 1000, height: 300)) == 5 ..< 15)
        #expect(grid.indices(in: CGRect(x: 0, y: 5000, width: 1000, height: 300)).isEmpty)
        #expect(GridGeometry(itemCount: 0, width: 1000, targetTileSide: 160, gutter: 8, inset: 16, captionHeight: 0)
            .indices(in: CGRect(x: 0, y: 0, width: 1000, height: 1000)).isEmpty)
    }

    @Test func hitTestingIgnoresGutters() {
        #expect(grid.index(at: CGPoint(x: 20, y: 20)) == 0)
        #expect(grid.index(at: CGPoint(x: 16 + 187 + 4, y: 20)) == nil)
        #expect(grid.index(at: CGPoint(x: 16 + 195 + 1, y: 16 + 215 + 1)) == 6)
        #expect(grid.index(at: CGPoint(x: 900, y: 16 + 4 * 215 + 10)) == nil) // past the last item
    }

    @Test func marqueeSelectsIntersectingTilesOnly() {
        let rect = CGRect(x: 100, y: 100, width: 150, height: 150)
        #expect(grid.indices(intersecting: rect) == [0, 1, 5, 6])
    }

    @Test func keyboardMovesAreClamped() {
        #expect(grid.index(from: 6, moving: .left, rowsPerPage: 2) == 5)
        #expect(grid.index(from: 4, moving: .right, rowsPerPage: 2) == 5)
        #expect(grid.index(from: 6, moving: .up, rowsPerPage: 2) == 1)
        #expect(grid.index(from: 2, moving: .up, rowsPerPage: 2) == 2)
        #expect(grid.index(from: 17, moving: .down, rowsPerPage: 2) == 22)
        #expect(grid.index(from: 21, moving: .down, rowsPerPage: 2) == 21)
        #expect(grid.index(from: 1, moving: .pageDown, rowsPerPage: 2) == 11)
        #expect(grid.index(from: 7, moving: .pageUp, rowsPerPage: 2) == 2)
        #expect(grid.index(from: 7, moving: .home, rowsPerPage: 2) == 0)
        #expect(grid.index(from: 7, moving: .end, rowsPerPage: 2) == 22)
    }
}

struct SelectionModelTests {
    private let order = OrderedIDs([10, 11, 12, 13, 14, 15])

    @Test func clickToggleAndShiftRange() {
        var selection = SelectionModel()
        selection.select(11)
        selection.extend(to: 13, in: order)
        #expect(selection.selected == [11, 12, 13])
        selection.extend(to: 10, in: order)
        #expect(selection.selected == [10, 11])
        selection.toggle(15)
        #expect(selection.selected == [10, 11, 15])
        selection.extend(to: 13, in: order)
        #expect(selection.selected == [10, 11, 13, 14, 15])
        selection.toggle(10)
        #expect(selection.selected == [11, 13, 14, 15])
        #expect(selection.focus == 10)
    }

    @Test func marqueeReplacesOrAdds() {
        var selection = SelectionModel()
        selection.select(10)
        selection.beginMarquee(adding: true)
        selection.marquee([12, 13])
        #expect(selection.selected == [10, 12, 13])
        selection.marquee([13])
        #expect(selection.selected == [10, 13])
        selection.commitMarquee(focus: 13)
        selection.beginMarquee(adding: false)
        #expect(selection.isEmpty)
        selection.marquee([15])
        #expect(selection.selected == [15])
    }

    @Test func selectAllAndRetain() {
        var selection = SelectionModel()
        selection.selectAll(order)
        #expect(selection.selected.count == 6)
        selection.retain(onlyIn: OrderedIDs([12, 99]))
        #expect(selection.selected == [12])
        #expect(selection.focus == nil)
    }
}

struct FolderTreeAndFilterTests {
    @Test func treeIsBuiltAndSortedNaturally() throws {
        let folders = [
            Folder(id: 1, rootID: 1, parentID: nil, relativePath: "", name: "Photos", state: .present),
            Folder(id: 2, rootID: 1, parentID: 1, relativePath: "Trip 10", name: "Trip 10", state: .present),
            Folder(id: 3, rootID: 1, parentID: 1, relativePath: "Trip 9", name: "Trip 9", state: .present),
            Folder(id: 4, rootID: 1, parentID: 3, relativePath: "Trip 9/Day 1", name: "Day 1", state: .present),
        ]
        let tree = try #require(FolderNode.tree(from: folders))
        #expect(tree.folder.name == "Photos")
        #expect(tree.children?.map(\.folder.name) == ["Trip 9", "Trip 10"])
        #expect(tree.children?.first?.children?.map(\.folder.name) == ["Day 1"])
        #expect(tree.children?.last?.children == nil)
        #expect(tree.find(4)?.folder.name == "Day 1")
        #expect(tree.find(99) == nil)
        #expect(tree.path(to: 4)?.map(\.folder.name) == ["Photos", "Trip 9", "Day 1"])
        #expect(tree.path(to: 99) == nil)
    }

    @Test func foldersWithoutMediaBelowAreLeftOut() throws {
        let folders = [
            Folder(id: 1, rootID: 1, parentID: nil, relativePath: "", name: "Root", state: .present),
            Folder(id: 2, rootID: 1, parentID: 1, relativePath: "Empty", name: "Empty", state: .present),
            Folder(id: 3, rootID: 1, parentID: 1, relativePath: "Outer", name: "Outer", state: .present),
            Folder(id: 4, rootID: 1, parentID: 3, relativePath: "Outer/Deep", name: "Deep", state: .present),
            Folder(id: 5, rootID: 1, parentID: 3, relativePath: "Outer/Docs", name: "Docs", state: .present),
        ]
        let tree = try #require(FolderNode.tree(from: folders, withMedia: [4]))
        #expect(tree.children?.map(\.folder.name) == ["Outer"]) // no media itself, but below
        #expect(tree.find(3)?.children?.map(\.folder.name) == ["Deep"])
        let bare = try #require(FolderNode.tree(from: folders, withMedia: []))
        #expect(bare.folder.name == "Root" && bare.children == nil)
    }

    @Test func atLeastOneKindStaysOn() {
        let all = Set(MediaKind.allCases)
        #expect(all.toggling(.video) == [.photo, .audio])
        #expect(Set([MediaKind.photo]).toggling(.photo) == [.photo])
        #expect(Set([MediaKind.photo]).toggling(.audio) == [.photo, .audio])
    }

    @Test func viewStateRoundTripsAndToleratesMissingKeys() throws {
        var state = LibraryViewState()
        state.folderID = 7
        state.kinds = [.audio]
        state.sort = .dateCaptured
        state.selectedIDs = [1, 2]
        state.previewVisible = false
        state.previewWidth = 420
        let decoded = try JSONDecoder().decode(LibraryViewState.self, from: JSONEncoder().encode(state))
        #expect(decoded == state)
        let partial = try JSONDecoder().decode(LibraryViewState.self, from: Data(#"{"sort":"bogus","kinds":[]}"#.utf8))
        #expect(partial == LibraryViewState())
        // A state saved before the preview pane existed keeps its folder and shows the pane at the default width.
        let older = try JSONDecoder().decode(LibraryViewState.self, from: Data(#"{"folderID":3,"tileSide":200}"#.utf8))
        #expect(older.folderID == 3)
        #expect(older.previewVisible)
        #expect(older.previewWidth == LibraryViewState().previewWidth)
    }

    @Test func splitViewStateRoundTripsAndDefaultsOff() throws {
        var state = LibraryViewState()
        state.splitMode = .stacked
        state.splitFraction = 0.3
        state.lastSplit = LibraryViewState.SplitMode.stacked.rawValue
        let decoded = try JSONDecoder().decode(LibraryViewState.self, from: JSONEncoder().encode(state))
        #expect(decoded == state)
        // A state from before the split view, or with an unknown mode, opens one pane.
        let older = try JSONDecoder().decode(LibraryViewState.self, from: Data(#"{"splitMode":"diagonal"}"#.utf8))
        #expect(older.splitMode == .off)
        #expect(older.splitFraction == 0.5)
    }
}

struct PagerTests {
    @Test func windowIsCurrentThenNearestNeighbors() {
        #expect(Pager.window(around: 5, count: 10) == [5, 6, 4, 7, 3])
        #expect(Pager.window(around: 0, count: 10) == [0, 1, 2])
        #expect(Pager.window(around: 9, count: 10) == [9, 8, 7])
        #expect(Pager.window(around: 0, count: 1) == [0])
        #expect(Pager.window(around: 3, count: 0).isEmpty)
    }

    @Test func movesClampWithoutWrapping() {
        #expect(Pager.move(0, by: -1, count: 5) == 0)
        #expect(Pager.move(4, by: 1, count: 5) == 4)
        #expect(Pager.move(2, by: 1, count: 5) == 3)
        #expect(Pager.move(0, by: 1, count: 0) == 0)
    }
}
