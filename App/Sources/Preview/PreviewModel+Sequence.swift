import CoreGraphics
import JGModel
import JGThumbs
import QuartzCore

/// A folded image sequence in the previews (W-86): a timeline of its frames. Dragging shows the frame under the
/// pointer; play runs at 24 frames a second from the frame shown and stops at the last. Each frame shows its large
/// thumbnail; only the newest request loads, so a drag never queues frames, and while playing a frame not ready is
/// skipped instead of slowing the clock.
extension PreviewModel {
    func beginSequence(_ frames: [Int64]) {
        sequence = SequencePlayback(frameCount: frames.count)
        sequenceAssets = []
        let store = libraryStore
        Task { [weak self] in
            let assets = await (try? store.assets(ids: frames)) ?? []
            guard let self, sequence?.frameCount == frames.count else { return }
            sequenceAssets = assets
        }
    }

    func endSequence() {
        sequenceClock?.cancel()
        sequenceClock = nil
        frameLoad?.cancel()
        frameLoad = nil
        sequence = nil
        sequenceAssets = []
        headPicture = nil
    }

    /// The timeline was dragged to `frame`.
    func scrubSequence(to frame: Int) {
        guard var playback = sequence else { return }
        playback.scrub(to: frame)
        sequence = playback
        sequenceClock?.cancel()
        showFrame(playback.index)
    }

    func toggleSequencePlay() {
        guard var playback = sequence else { return }
        if playback.isPlaying {
            playback.pause()
            sequence = playback
            sequenceClock?.cancel()
            return
        }
        playback.play(at: CACurrentMediaTime())
        sequence = playback
        showFrame(playback.index)
        sequenceClock?.cancel()
        sequenceClock = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(0.5 / SequencePlayback.framesPerSecond))
                guard let self, var playback = sequence, playback.isPlaying else { return }
                let changed = playback.tick(at: CACurrentMediaTime()) { self.isFrameReady($0) }
                sequence = playback
                if changed {
                    showFrame(playback.index)
                } else {
                    // Not ready: ask for it (the newest request only) and let the clock go on.
                    requestFrame(playback.due(at: CACurrentMediaTime()))
                }
            }
        }
    }

    private func frameAsset(_ index: Int) -> Asset? {
        sequenceAssets.indices.contains(index) ? sequenceAssets[index] : nil
    }

    private func cachedFrame(_ index: Int) -> CGImage? {
        guard let asset = frameAsset(index), case let .some(.some(image)) = thumbnailService(for: asset)
            .cachedThumbnail(for: request(asset, .large))
        else { return nil }
        return image
    }

    private func isFrameReady(_ index: Int) -> Bool {
        index == 0 || cachedFrame(index) != nil
    }

    /// Shows frame `index`: the first frame's own decode, else the frame's large thumbnail (loaded if needed).
    private func showFrame(_ index: Int) {
        if index == 0, let head = headPicture ?? cachedFrame(0) {
            frameLoad?.cancel()
            picture = head
        } else if let image = cachedFrame(index) {
            frameLoad?.cancel()
            picture = image
        } else {
            requestFrame(index)
        }
    }

    /// Loads frame `index`, dropping any older request; it shows if it is still the frame wanted.
    private func requestFrame(_ index: Int) {
        guard let asset = frameAsset(index) else { return }
        frameLoad?.cancel()
        let service = thumbnailService(for: asset)
        let request = request(asset, .large)
        frameLoad = Task { [weak self] in
            let image = await service.thumbnail(for: request, priority: .visible)
            guard !Task.isCancelled, let self, let image, sequence?.index == index else { return }
            picture = image
        }
    }
}
