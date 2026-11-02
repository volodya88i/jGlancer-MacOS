import JGModel
import JGStore

/// Image sequences in the grid (D-84, W-81): runs of numbered frames fold into their first frame. Folding lasts for
/// the session; actions, selections and drags on a folded tile take all its frames; viewers show every frame.
extension LibraryModel {
    /// Finds the sequences of the current query in the background, then folds them.
    func findSequences() {
        sequenceTask?.cancel()
        guard foldsSequences, !isSearching else {
            setSequences([])
            return
        }
        let query = query
        let store = store
        sequenceTask = Task { [weak self] in
            let members = await (try? store.sequenceMembers(for: query)) ?? []
            let found = await Task.detached(priority: .utility) { ImageSequences.find(in: members) }.value
            guard !Task.isCancelled else { return }
            self?.setSequences(found)
        }
    }

    private func setSequences(_ found: [ImageSequence]) {
        let byHead = Dictionary(uniqueKeysWithValues: found.map { ($0.head, $0) })
        guard byHead != sequences else { return }
        sequences = byHead
        var heads: [Int64: Int64] = [:]
        for sequence in found {
            for frame in sequence.frames {
                heads[frame] = sequence.head
            }
        }
        sequenceHeads = heads
        lastSequenceToggle = nil
        showRefs(folded(allRefs))
    }

    /// `refs` without the frames (all but the head) of folded sequences.
    func folded(_ refs: [AssetRef]) -> [AssetRef] {
        guard !sequenceHeads.isEmpty else { return refs }
        return refs.filter { ref in
            guard let head = sequenceHeads[ref.id], head != ref.id else { return true }
            return unfoldedSequences.contains(head)
        }
    }

    /// The sequence whose head is `id`, folded or not.
    func sequence(headedBy id: Int64) -> ImageSequence? {
        sequences[id]
    }

    func isFolded(_ head: Int64) -> Bool {
        sequences[head] != nil && !unfoldedSequences.contains(head)
    }

    /// Unfolds a folded sequence, folds an unfolded one (its badge, a double-click).
    func toggleSequence(_ head: Int64) {
        guard sequences[head] != nil else { return }
        let unfolding = !unfoldedSequences.contains(head)
        if unfolding {
            unfoldedSequences.insert(head)
        } else {
            unfoldedSequences.remove(head)
        }
        lastSequenceToggle = (head, unfolding)
        showRefs(folded(allRefs))
        onSequenceToggle?()
    }

    /// `ids` with every folded head replaced by all its frames (what actions and drags take).
    func expandingSequences(_ ids: [Int64]) -> [Int64] {
        ids.flatMap { id in
            isFolded(id) ? sequences[id]?.frames ?? [id] : [id]
        }
    }
}
