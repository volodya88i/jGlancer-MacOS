import AppKit
import Foundation
import JGDesign
import SwiftUI

/// -JGMusicCheck <png>: opens the first song in the audio player, analyzes it, sets a target pitch of +2 and a target
/// tempo, logs what the button and the rates say, snapshots the player and the key and tempo panel (D-106).
@MainActor
enum MusicCheck {
    static func run(_ appModel: AppModel, library: LibraryModel, snapshot: URL) async {
        guard let song = library.refs.first(where: { $0.kind == .audio }) else { return log("no song") }
        await appModel.openViewer(assetID: song.id)
        try? await Task.sleep(for: .milliseconds(800))
        guard let model = appModel.mediaViewer else { return log("no player") }
        log("before: \(model.musicLabel ?? "Key · BPM")")
        let began = Date()
        model.analyze()
        while model.isAnalyzing {
            try? await Task.sleep(for: .milliseconds(50))
        }
        log(String(format: "analyzed in %.2f s: bpm %@, key %@; button \"%@\"", Date().timeIntervalSince(began),
                   model.analysis?.bpmLabel ?? "-", model.analysis?.key?.label ?? "-", model.musicLabel ?? "-"))
        model.setTargetPitch(2)
        log(String(format: "pitch +2: rate %.4f, keeps pitch %@, button \"%@\"", model.playback.rate,
                   "\(model.playback.preservesPitch)", model.musicLabel ?? "-"))
        render(model, to: snapshot.deletingPathExtension().appendingPathExtension("panel.png"))
        try? await Task.sleep(for: .milliseconds(400))
        if let window = DeveloperHooks.mainWindow {
            DeveloperHooks.snapshot(window, to: snapshot)
        }
        model.setTargetTempo(140)
        log(String(format: "tempo 140: rate %.4f, button \"%@\"", model.playback.rate, model.musicLabel ?? "-"))
        model.tuning.clearTarget()
        log(String(format: "reset: rate %.2f, keeps pitch %@, targeted %@", model.playback.rate,
                   "\(model.playback.preservesPitch)", "\(model.tuning.isTargeted)"))
        try? await Task.sleep(for: .milliseconds(400))
        if let window = DeveloperHooks.mainWindow {
            DeveloperHooks.snapshot(window, to: snapshot.deletingPathExtension().appendingPathExtension("reset.png"))
        }
    }

    /// The panel drawn off screen in the window's appearance (a popover is a window of its own).
    private static func render(_ model: MediaViewerModel, to url: URL) {
        let view = NSHostingView(rootView: MusicPanel(model: model).background(JGColor.bgPopup))
        view.appearance = DeveloperHooks.mainWindow?.effectiveAppearance
        view.frame = NSRect(origin: .zero, size: view.fittingSize)
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
    }

    private static func log(_ line: String) {
        FileHandle.standardError.write(Data("music check: \(line)\n".utf8))
    }
}
