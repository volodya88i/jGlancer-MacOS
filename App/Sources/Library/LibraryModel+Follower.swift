import JGModel

/// The second pane of a split view (D-89, W-66): a follower of the main pane. Roots, folder trees, albums, indexing
/// and undo belong to the main pane; this one has its own folder or album, filters, search, sort, tile size and
/// selection.
extension LibraryModel {
    /// Starts following `leader`: mirrors it, shows its folder unless one was saved, loads the index.
    func startFollowing(_ leader: LibraryModel) {
        leader.follower = self
        decorCrosshairs = leader.decorCrosshairs
        animatesGrid = leader.animatesGrid
        reducesMotion = leader.reducesMotion
        foldsSequences = leader.foldsSequences
        mirror(leader)
        // A saved folder stays (the trees may still be loading; `mirror` drops it if it is gone).
        if state.folderID == nil, state.albumID == nil {
            updateState { $0.folderID = leader.state.folderID }
        }
        reloadQuery()
    }

    func stopFollowing(_ leader: LibraryModel) {
        if leader.follower === self {
            leader.follower = nil
        }
        sequenceTask?.cancel()
    }

    /// Takes the leader's roots, trees and albums; a folder or album that vanished falls back to the first root.
    func mirror(_ leader: LibraryModel) {
        guard isFollower else { return }
        if roots != leader.roots {
            setRoots(leader.roots)
        }
        if trees != leader.trees {
            trees = leader.trees
        }
        if albums != leader.albums {
            albums = leader.albums
        }
        if albumMemberships != leader.albumMemberships {
            albumMemberships = leader.albumMemberships
        }
        if let id = state.albumID, !albums.isEmpty, !albums.contains(where: { $0.id == id }) {
            leaveAlbum()
        }
        // Only once every root's tree is in: a folder of a tree still loading is not gone.
        if state.albumID == nil, let id = state.folderID, !trees.isEmpty, trees.count >= roots.count, folder(id: id) == nil,
           let top = roots.first.flatMap({ trees[$0.id]?.folder.id })
        {
            select(folderID: top)
        }
    }
}
