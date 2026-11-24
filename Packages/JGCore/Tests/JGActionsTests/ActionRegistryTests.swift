import JGModel
import Testing
@testable import JGActions

struct ActionRegistryTests {
    let phase6: Set<ActionFeature> = [.openWith]
    let everything: Set<ActionFeature> = [.openWith, .fileOperations, .albums, .flags]

    func ids(_ menu: [[(id: ActionID, isEnabled: Bool)]]) -> [[ActionID]] {
        menu.map { $0.map(\.id) }
    }

    @Test func phase6MenuForOnePhoto() {
        let menu = ActionRegistry.menu(
            for: ActionSelection(fileCount: 1, kinds: [.photo], place: .library), features: phase6, primaryAppKinds: []
        )
        #expect(ids(menu) == [[.open, .quickPreview, .openWith], [.setFolderIcon], [.getInfo, .revealInFinder, .copyPath, .copy]])
    }

    @Test func editInPrimaryAppNeedsAPrimaryForTheOnlyKind() {
        let audio = ActionSelection(fileCount: 2, kinds: [.audio], place: .library)
        let mixed = ActionSelection(fileCount: 2, kinds: [.audio, .photo], place: .library)
        #expect(ActionRegistry.availability(.editInPrimaryApp, for: audio, features: phase6, primaryAppKinds: [.audio]) == .enabled)
        #expect(ActionRegistry.availability(.editInPrimaryApp, for: audio, features: phase6, primaryAppKinds: [.photo]) == .hidden)
        #expect(ActionRegistry.availability(.editInPrimaryApp, for: mixed, features: phase6, primaryAppKinds: [.audio, .photo]) == .hidden)
    }

    @Test func renameTakesAnyKind() {
        let photos = ActionSelection(fileCount: 3, kinds: [.photo], place: .library)
        let video = ActionSelection(fileCount: 1, kinds: [.video], place: .library)
        #expect(ActionRegistry.availability(.rename, for: photos, features: everything, primaryAppKinds: []) == .enabled)
        #expect(ActionRegistry.availability(.rename, for: video, features: everything, primaryAppKinds: []) == .enabled)
    }

    @Test func fullMenuEndsWithTrashAloneAndViewerHasNoQuickPreview() {
        let selection = ActionSelection(fileCount: 1, kinds: [.photo], place: .viewer)
        let menu = ids(ActionRegistry.menu(for: selection, features: everything, primaryAppKinds: [.photo]))
        #expect(menu.last == [.moveToTrash])
        #expect(!menu.joined().contains(.quickPreview))
        #expect(menu.joined().contains(.copyTo))
        #expect(!menu.joined().contains(.moveTo))
        #expect(!menu.joined().contains(.rename))
        #expect(menu.first == [.openWith, .editInPrimaryApp])
        #expect(menu.contains([.flag]))
    }

    @Test func songsCanPlayInTheMiniPlayer() {
        let songs = ActionSelection(fileCount: 2, kinds: [.audio], place: .library)
        let mixed = ActionSelection(fileCount: 2, kinds: [.audio, .photo], place: .library)
        let viewer = ActionSelection(fileCount: 1, kinds: [.audio], place: .viewer)
        #expect(ActionRegistry.availability(.playInMiniPlayer, for: songs, features: [], primaryAppKinds: []) == .enabled)
        #expect(ActionRegistry.availability(.playInMiniPlayer, for: mixed, features: [], primaryAppKinds: []) == .hidden)
        // The song of the player goes on in the mini player; a video does not.
        #expect(ActionRegistry.availability(.playInMiniPlayer, for: viewer, features: [], primaryAppKinds: []) == .enabled)
        let video = ActionSelection(fileCount: 1, kinds: [.video], place: .viewer)
        #expect(ActionRegistry.availability(.playInMiniPlayer, for: video, features: [], primaryAppKinds: []) == .hidden)
    }

    @Test func onlySongsSplitIntoStems() {
        let songs = ActionSelection(fileCount: 3, kinds: [.audio], place: .library)
        let player = ActionSelection(fileCount: 1, kinds: [.audio], place: .viewer)
        let mixed = ActionSelection(fileCount: 2, kinds: [.audio, .video], place: .library)
        #expect(ActionRegistry.availability(.splitStems, for: songs, features: [], primaryAppKinds: []) == .enabled)
        #expect(ActionRegistry.availability(.splitStems, for: player, features: [], primaryAppKinds: []) == .enabled)
        #expect(ActionRegistry.availability(.splitStems, for: mixed, features: [], primaryAppKinds: []) == .hidden)
    }

    @Test func compareTakesExactlyTwoPhotos() {
        let mixed = ActionSelection(fileCount: 2, kinds: [.audio, .photo], place: .library)
        let twoPhotos = ActionSelection(fileCount: 2, kinds: [.photo], place: .album)
        let threePhotos = ActionSelection(fileCount: 3, kinds: [.photo], place: .library)
        #expect(ActionRegistry.availability(.compare, for: twoPhotos, features: [], primaryAppKinds: []) == .enabled)
        #expect(ActionRegistry.availability(.compare, for: threePhotos, features: [], primaryAppKinds: []) == .hidden)
        #expect(ActionRegistry.availability(.compare, for: mixed, features: [], primaryAppKinds: []) == .hidden)
        #expect(ShortcutCommand.compare.defaultShortcut == ActionShortcut("c", [.command, .control]))
    }

    @Test func nothingForAnEmptySelection() {
        let empty = ActionSelection(fileCount: 0, kinds: [], place: .library)
        #expect(ActionRegistry.menu(for: empty, features: everything, primaryAppKinds: []).isEmpty)
    }

    @Test func plainKeysStayOutOfTheMenuBar() {
        #expect(ActionRegistry.shortcut(for: .quickPreview)?.isMenuBarEquivalent == false)
        #expect(ActionRegistry.shortcut(for: .open)?.isMenuBarEquivalent == false)
        #expect(ActionRegistry.shortcut(for: .getInfo)?.isMenuBarEquivalent == true)
        let all = ActionRegistry.sections.joined()
        #expect(Set(all).count == ActionID.allCases.count)
    }

    @Test func onePhotoInTheLibraryCanBeItsFoldersIcon() {
        func availability(_ count: Int, _ kinds: Set<MediaKind>, _ place: ActionSelection.Place) -> ActionAvailability {
            ActionRegistry.availability(
                .setFolderIcon, for: ActionSelection(fileCount: count, kinds: kinds, place: place), features: everything,
                primaryAppKinds: []
            )
        }
        #expect(availability(1, [.photo], .library) == .enabled)
        #expect(availability(1, [.photo], .album) == .enabled)
        #expect(availability(2, [.photo], .library) == .hidden)
        #expect(availability(1, [.video], .library) == .hidden)
        #expect(availability(1, [.photo], .viewer) == .hidden)
    }

    @Test func albumActionsAppearInAlbums() {
        let inAlbum = ActionSelection(fileCount: 2, kinds: [.photo], place: .album)
        let inLibrary = ActionSelection(fileCount: 1, kinds: [.photo], place: .library)
        #expect(ActionRegistry.availability(.removeFromAlbum, for: inAlbum, features: everything, primaryAppKinds: []) == .enabled)
        #expect(ActionRegistry.availability(.setAlbumCover, for: inAlbum, features: everything, primaryAppKinds: []) == .disabled)
        #expect(ActionRegistry.availability(.removeFromAlbum, for: inLibrary, features: everything, primaryAppKinds: []) == .hidden)
        #expect(ActionRegistry.availability(.addToAlbum, for: inLibrary, features: everything, primaryAppKinds: []) == .enabled)
        #expect(ActionRegistry.availability(.quickPreview, for: inAlbum, features: everything, primaryAppKinds: []) == .enabled)
    }
}
