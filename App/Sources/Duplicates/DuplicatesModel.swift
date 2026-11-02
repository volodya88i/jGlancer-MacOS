import Foundation
import JGActions
import JGModel
import JGStore
import JGThumbs
import Observation

/// Find Duplicates (W-78): copies found by size and quick hash, the extra ones ticked. "Move N to Trash" compares
/// each ticked copy byte for byte with the copy that stays first; copies that differ are left alone and reported,
/// the rest go to the Trash as one undoable operation.
@MainActor
@Observable
final class DuplicatesModel {
    private(set) var plan = DuplicatePlan(groups: [])
    /// Files whose quick hash is still being read.
    private(set) var pending = 0
    private(set) var isScanning = false
    private(set) var isTrashing = false
    /// The outcome of the last Move to Trash.
    private(set) var message: String?

    @ObservationIgnored let store: LibraryStore
    @ObservationIgnored let thumbnails: ThumbnailService
    /// Moves files to the Trash as one undoable operation.
    @ObservationIgnored var onTrash: ([URL]) -> Void = { _ in }

    init(store: LibraryStore, thumbnails: ThumbnailService) {
        self.store = store
        self.thumbnails = thumbnails
    }

    func scan() async {
        isScanning = true
        defer { isScanning = false }
        guard let found = try? await store.duplicateCandidates() else { return }
        plan = DuplicatePlan(groups: found.groups)
        pending = found.pending
    }

    /// Ticks or unticks a copy; a beep when it is the last unticked copy of its group.
    func toggle(_ id: Int64) -> Bool {
        plan.toggle(id)
    }

    func moveTickedToTrash() async {
        let removals = plan.removals.map { (id: $0.copy.id, name: $0.copy.name, copy: $0.copy.url, kept: $0.kept.url) }
        guard !removals.isEmpty, !isTrashing else { return }
        isTrashing = true
        message = nil
        let checked = await Task.detached(priority: .userInitiated) {
            removals.map { (removal: $0, isSame: ByteCompare.identical($0.copy, $0.kept)) }
        }.value
        isTrashing = false
        let same = checked.filter(\.isSame).map(\.removal)
        let differ = checked.filter { !$0.isSame }.map(\.removal.name)
        onTrash(same.map(\.copy))
        message = Self.report(moved: same.count, differ: differ)
        let gone = Set(same.map(\.id))
        plan = DuplicatePlan(groups: plan.groups.map { $0.copies.filter { !gone.contains($0.id) } })
    }

    private static func report(moved: Int, differ: [String]) -> String {
        let moved = String(localized: "Moved \(moved) to the Trash.", comment: "Find Duplicates: outcome; the argument is a count")
        guard !differ.isEmpty else { return moved }
        let names = differ.joined(separator: ", ")
        return moved + " " + String(
            localized: "Not the same byte for byte, left alone: \(names)",
            comment: "Find Duplicates: copies whose contents differ; the argument is a list of file names"
        )
    }
}
