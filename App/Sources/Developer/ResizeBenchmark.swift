import AppKit
import Foundation
import JGModel

/// -JGResizeBenchmark: resizes the window in 40 steps, as a live resize does, and logs the time per step — with the
/// library alone, then with the first song open in the player (D-112).
@MainActor
enum ResizeBenchmark {
    static func run(_ appModel: AppModel, library: LibraryModel) async {
        try? await Task.sleep(for: .milliseconds(1000))
        guard let window = DeveloperHooks.mainWindow else { return }
        log("library: \(steps(window))")
        for kind in [MediaKind.audio, .photo, .video] {
            guard let file = library.refs.first(where: { $0.kind == kind }) else { continue }
            await appModel.openViewer(assetID: file.id)
            try? await Task.sleep(for: .milliseconds(1000))
            log("\(kind) viewer: \(steps(window))")
            appModel.closeViewer()
            try? await Task.sleep(for: .milliseconds(500))
        }
    }

    /// Average and worst milliseconds of a resize step, laid out and drawn.
    private static func steps(_ window: NSWindow) -> String {
        let start = window.frame
        var times: [Double] = []
        for step in 0 ..< 40 {
            let grow = CGFloat(step < 20 ? step : 40 - step) * 12
            var frame = start
            frame.size.width += grow
            frame.size.height += grow / 2
            let began = Date()
            window.setFrame(frame, display: true)
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
            CATransaction.flush()
            times.append(Date().timeIntervalSince(began) * 1000)
        }
        window.setFrame(start, display: true)
        let average = times.reduce(0, +) / Double(times.count)
        return String(format: "%.1f ms average, %.1f ms worst", average, times.max() ?? 0)
    }

    private static func log(_ line: String) {
        FileHandle.standardError.write(Data("resize benchmark: \(line)\n".utf8))
    }
}
