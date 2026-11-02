import AppKit
import JGModel
import JGSettings

/// Settings pushed into the app's parts, and the files the actions apply to.
extension AppModel {
    // MARK: Settings

    /// Pushes settings into the parts that keep their own copy.
    func apply(_ settings: AppSettings) {
        preview?.autoplayInPreview = settings.autoplayInPreview
        mediaViewer?.segmentKeepsAudioFormat = settings.segmentKeepsAudioFormat
        let reducesMotion = settings.reduceMotion || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        for pane in [library, secondPane].compactMap(\.self) {
            pane.decorCrosshairs = settings.crosshairMarks
            pane.reducesMotion = reducesMotion
            pane.animatesGrid = settings.animatesGrid && !reducesMotion
            pane.foldsSequences = settings.foldsSequences
        }
    }

    // MARK: Actions

    /// After a flag change: tiles and stars show the new flags.
    func flagsChanged() {
        library?.filesChanged()
        secondPane?.filesChanged()
        flagBook.changed()
    }

    /// The file in the open viewer as an action target.
    var viewerTarget: ActionTarget? {
        switch viewer {
        case let .photo(model):
            guard let photo = model.currentPhoto else { return nil }
            return ActionTarget(
                place: .viewer, assetIDs: photo.assetID.map { [$0] } ?? [], kinds: [.photo], count: 1, sample: photo.url,
                urls: { [photo.url] }
            )
        case let .media(model):
            guard let item = model.current else { return nil }
            return ActionTarget(
                place: .viewer, assetIDs: item.assetID.map { [$0] } ?? [], kinds: [item.kind], count: 1, sample: item.url,
                urls: { [item.url] }
            )
        case .compare:
            return compareTarget()
        case nil:
            return nil
        }
    }

    /// What the menu bar's actions apply to: the viewer's file, else the library selection.
    var currentTarget: ActionTarget? {
        viewerTarget ?? activeLibrary?.actionTarget(sample: preview?.asset?.url)
    }

    /// The viewer's file went to the Trash: show the next one, or go back to the library when none is left.
    func viewerRemovedCurrentFile() {
        let hasMore = switch viewer {
        case let .photo(model): model.removeCurrent()
        case let .media(model): model.playback.removeCurrent()
        case .compare, nil: true
        }
        if !hasMore {
            closeViewer()
        }
    }

    func viewerContextMenu() -> NSMenu? {
        viewerTarget.flatMap { ActionMenu.make(for: $0, performer: actions) }
    }
}
