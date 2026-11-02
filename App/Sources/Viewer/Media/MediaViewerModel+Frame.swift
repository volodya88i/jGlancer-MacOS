import AppKit
import JGPlayback

/// Saving the video frame on screen (D-80, W-75).
extension MediaViewerModel {
    /// The frame at the playhead, at the video's own size: a PNG next to the video, or (copying) to the pasteboard.
    /// A toast confirms. The task finishes even if the player closes meanwhile.
    func saveFrame(copying: Bool) {
        guard kind == .video, let item = current else { return }
        let seconds = playback.mediaSeconds
        let show = showMessage
        Task {
            do {
                let image = try await VideoFrame.image(of: item.url, at: seconds)
                if copying {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.writeObjects([NSImage(cgImage: image, size: .zero)])
                    show?(String(localized: "Frame copied", comment: "Toast: the video frame is on the pasteboard"))
                } else {
                    let saved = try await Task.detached { try VideoFrame.save(image, nextTo: item.url, at: seconds) }.value
                    show?(String(
                        localized: "Saved \(saved.lastPathComponent)",
                        comment: "Toast: the video frame was saved; the argument is the file name"
                    ))
                }
            } catch {
                show?(String(localized: "Can't save this frame", comment: "Toast: the video frame could not be read or written"))
            }
        }
    }
}
