import AVFoundation

/// The end of an item: play it again (loop), go on to the next, or stop.
extension PlaybackController {
    func itemDidEnd() {
        switch queue.endAction(loop: loops, autoAdvance: autoAdvance) {
        case .replay:
            seek(to: 0, precise: true)
            if matroska != nil {
                play()
            } else {
                player.play()
            }
        case let .advance(index):
            select(index)
        case .stop:
            if matroska != nil {
                isPlaying = false
            }
            setTime(duration ?? mediaSeconds, exact: true)
        }
    }
}
