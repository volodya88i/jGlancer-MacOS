import AppKit
import JGModel
import JGThumbs

/// Thumbnail loading of the grid (D-81). While scrolling, the visible tiles load first, then
/// the screen the speed predicts and the strip just past the edge; tiles that only fly past are not asked for.
/// Tiles that leave are not cancelled at once: they drop to background (at most `trailLimit`, oldest cancelled),
/// where they run one at a time and fill `cache.sqlite` without pushing visible thumbnails out of memory. When the
/// scroll stops, the visible tiles go first, a screen around them next, and the rest trickles along.
extension GridController {
    /// Background requests kept from tiles that flew past.
    static let trailLimit = 300

    @objc func scrolled() {
        prefetch.moved(to: Double(collectionView.visibleRect.minY), at: CACurrentMediaTime())
        settleTask?.cancel()
        settleTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(ScrollPrefetch.settleDelay))
            guard !Task.isCancelled, let self else { return }
            prefetch.stopped()
            updateWindow()
        }
        updateWindow()
    }

    @objc func viewportChanged() {
        updateWindow()
    }

    /// Asks for the visible tiles, then the areas ahead; lowers what left them to background.
    func updateWindow() {
        let geometry = layout.currentGeometry()
        let visibleRect = collectionView.visibleRect
        guard geometry.itemCount > 0, visibleRect.height > 0 else {
            cancelAllThumbnails()
            return
        }
        let refs = model.refs
        let visible = geometry.indices(in: visibleRect).filter { $0 < refs.count }
        let ahead = prefetch.aheadRects(visible: visibleRect, contentHeight: collectionView.bounds.height)
            .flatMap { geometry.indices(in: $0) }
            .filter { $0 < refs.count && !visible.contains($0) }
        let wanted = visible.map { refs[$0].id } + ahead.map { refs[$0].id }
        let missing = wanted.filter { rows[$0] == nil && !rowsInFlight.contains($0) }
        if !missing.isEmpty {
            fetchRows(missing)
        }
        lowerTilesThatLeft(keeping: Set(wanted))
        for index in visible {
            rows[refs[index].id].map { requestThumbnail($0, priority: .visible) }
        }
        for index in ahead {
            rows[refs[index].id].map { requestThumbnail($0, priority: .nearby) }
        }
    }

    /// Requests no longer wanted go to background; the oldest beyond `trailLimit` are cancelled.
    private func lowerTilesThatLeft(keeping wanted: Set<Int64>) {
        for (id, entry) in thumbnailTasks where !wanted.contains(id) && entry.priority > .background {
            thumbnailTasks[id] = (entry.task, .background)
            trail.append(id)
            if let asset = rows[id] {
                reprioritize(request(for: asset), to: .background)
            }
        }
        trail.removeAll { thumbnailTasks[$0]?.priority != .background }
        if trail.count > Self.trailLimit {
            for id in trail.prefix(trail.count - Self.trailLimit) {
                thumbnailTasks[id]?.task.cancel()
                thumbnailTasks[id] = nil
            }
            trail.removeFirst(trail.count - Self.trailLimit)
        }
    }

    /// Priority changes go to the service in order, as one batch with the latest wish per tile (separate tasks
    /// could arrive out of order and leave a visible tile in the background queue).
    private func reprioritize(_ request: ThumbnailRequest, to priority: ThumbnailPriority) {
        pendingPriorities[request.assetID] = (request, priority)
        guard priorityFlush == nil else { return }
        let service = model.thumbnails
        priorityFlush = Task { [weak self] in
            while let self, !pendingPriorities.isEmpty {
                let batch = pendingPriorities.values.map { ($0.0, $0.1) }
                pendingPriorities.removeAll()
                await service.reprioritize(batch)
            }
            self?.priorityFlush = nil
        }
    }

    func fetchRows(_ ids: [Int64]) {
        rowsInFlight.formUnion(ids)
        let store = model.store
        Task { [weak self] in
            let assets = await (try? store.assets(ids: ids)) ?? []
            guard let self else { return }
            rowsInFlight.subtract(ids)
            rowQueue += assets.filter { rows[$0.id] == nil }.map(\.id)
            for asset in assets {
                rows[asset.id] = asset
            }
            if rowQueue.count > Self.rowCapacity {
                for id in rowQueue.prefix(rowQueue.count - Self.rowCapacity) {
                    rows[id] = nil
                }
                rowQueue.removeFirst(rowQueue.count - Self.rowCapacity)
            }
            reconfigureVisibleItems()
            updateWindow()
        }
    }

    func request(for asset: Asset) -> ThumbnailRequest {
        ThumbnailRequest(
            assetID: asset.id, url: asset.url, kind: asset.kind, typeIdentifier: asset.typeIdentifier,
            modifiedAt: asset.modifiedAt, duration: asset.duration, bucket: currentBucket
        )
    }

    private func requestThumbnail(_ asset: Asset, priority: ThumbnailPriority) {
        let request = request(for: asset)
        if let cached = model.thumbnails.cachedThumbnail(for: request) {
            // In memory already (perhaps through another request): make sure the tile shows it.
            show(cached, for: asset.id)
            return
        }
        if let existing = thumbnailTasks[asset.id] {
            if existing.priority < priority {
                // A tile coming back (or into view): its request moves up instead of starting again.
                thumbnailTasks[asset.id] = (existing.task, priority)
                reprioritize(request, to: priority)
            }
            return
        }
        let service = model.thumbnails
        let id = asset.id
        let task = Task { [weak self] in
            let image = await service.thumbnail(for: request, priority: priority)
            guard !Task.isCancelled, let self else { return }
            thumbnailTasks[id] = nil
            show(image, for: id)
        }
        thumbnailTasks[id] = (task, priority)
    }

    private func show(_ image: CGImage?, for id: Int64) {
        guard let index = model.order.index(of: id),
              let item = collectionView.item(at: IndexPath(item: index, section: 0)) as? ThumbnailItem,
              item.assetID == id, item.tile?.image !== image || item.tile?.isLoading == true
        else { return }
        item.tile?.image = image
        item.tile?.isLoading = false
        if image != nil {
            LaunchMetrics.markFirstTile()
        }
    }

    func cancelAllThumbnails() {
        for entry in thumbnailTasks.values {
            entry.task.cancel()
        }
        thumbnailTasks.removeAll()
        trail.removeAll()
    }
}
