import AppKit
import Foundation

/// -JGSequencePreviewCheck <png> (a folder with an image sequence): selects the folded sequence, drags its preview
/// timeline to frame 20, snapshots, plays from the start for 0.6 s and logs the frames; unfolds it and logs that the
/// timeline went away (W-86).
@MainActor
enum SequencePreviewCheck {
    static func run(_ appModel: AppModel, library: LibraryModel, snapshot: URL) async {
        try? await Task.sleep(for: .seconds(1.5))
        guard let head = library.sequences.keys.min(), let preview = appModel.preview, let window = DeveloperHooks.mainWindow else {
            log("no sequence")
            return
        }
        library.selection.select(head)
        try? await Task.sleep(for: .milliseconds(800))
        guard let sequence = preview.sequence else {
            log("the preview shows no timeline")
            return
        }
        log("timeline of \(sequence.frameCount) frames")
        preview.scrubSequence(to: 19)
        try? await Task.sleep(for: .milliseconds(600))
        log("dragged to \(preview.sequence.map { "\($0.index + 1) / \($0.frameCount)" } ?? "-"), picture \(preview.picture != nil)")
        DeveloperHooks.snapshot(window, to: snapshot)
        preview.scrubSequence(to: 0)
        preview.toggleSequencePlay()
        try? await Task.sleep(for: .milliseconds(600))
        log("after 0.6 s of play: frame \(preview.sequence.map { $0.index + 1 } ?? -1), playing \(preview.sequence?.isPlaying == true)")
        try? await Task.sleep(for: .seconds(1.2))
        log("at the end: frame \(preview.sequence.map { $0.index + 1 } ?? -1), playing \(preview.sequence?.isPlaying == true)")
        library.toggleSequence(head)
        try? await Task.sleep(for: .milliseconds(600))
        log("unfolded: timeline \(preview.sequence != nil)")
        library.toggleSequence(head)
    }

    private static func log(_ line: String) {
        FileHandle.standardError.write(Data("sequence preview check: \(line)\n".utf8))
    }
}
