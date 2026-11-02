import Foundation
import JGActions
import JGModel

/// The files an action applies to: the library selection or the file in a viewer.
struct ActionTarget {
    let place: ActionSelection.Place
    /// Library assets, in display order (empty for a file outside the library).
    let assetIDs: [Int64]
    let kinds: Set<MediaKind>
    let count: Int
    /// A file known at once (the clicked or focused one), for the Open With suggestions.
    let sample: URL?
    /// All the files; library paths come from the store when an action runs.
    let urls: @MainActor () async -> [URL]

    var selection: ActionSelection {
        ActionSelection(fileCount: count, kinds: kinds, place: place)
    }

    /// The one kind of the files, if they share it.
    var kind: MediaKind? {
        kinds.count == 1 ? kinds.first : nil
    }
}
