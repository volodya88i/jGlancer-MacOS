import AppKit
import Foundation

/// `-JGScrollBenchmark <out.json>` (with `-JGAddFolder <photos>`, thumbnails not cached): the thumbnail loading of
/// the grid under a fast scroll (D-81). Scrolls at `-JGScrollSpeed` points per second (default 6000) for 3 s, stops,
/// and records how many visible tiles were still empty at the stop, the time until the screen is full, the CPU
/// during the scroll and over the 5 s after it, and the peak memory footprint (sampled every 100 ms). Then quits.
@MainActor
enum ScrollBenchmark {
    struct Result: Codable {
        var items = 0
        var pointsPerSecond = 0.0
        var lateFrames = 0
        var frames = 0
        var emptyVisibleAtStop = 0
        var visibleTiles = 0
        var screenFullAfterStopMs: Double?
        var cpuDuringScrollPercent = 0.0
        var cpuAfterStopPercent = 0.0
        var peakFootprintMB = 0.0
        var footprintAfterMB = 0.0
    }

    static func run(library: LibraryModel, output: URL) async {
        var result = Result()
        result.items = library.refs.count
        guard let scrollView = gridScrollView(), let grid = scrollView.documentView as? GridCollectionView else { return }
        try? await Task.sleep(for: .seconds(1))
        var peak = Benchmark.footprintMB()
        let sampler = Task {
            while !Task.isCancelled {
                peak = max(peak, Benchmark.footprintMB())
                try? await Task.sleep(for: .milliseconds(100))
            }
        }
        let speed = UserDefaults.standard.double(forKey: "JGScrollSpeed")
        result.pointsPerSecond = speed > 0 ? speed : 6000
        let cpuBefore = cpuSeconds()
        let scroll = await ScrollDriver(scrollView: scrollView, pointsPerSecond: result.pointsPerSecond).run(seconds: 3)
        result.cpuDuringScrollPercent = (cpuSeconds() - cpuBefore) / 3 * 100
        result.frames = scroll.frames
        result.lateFrames = scroll.lateFrames
        let stop = Date()
        let cpuStop = cpuSeconds()
        (result.emptyVisibleAtStop, result.visibleTiles) = emptyVisible(grid)
        while Date().timeIntervalSince(stop) < 5 {
            if result.screenFullAfterStopMs == nil, emptyVisible(grid).0 == 0 {
                result.screenFullAfterStopMs = Date().timeIntervalSince(stop) * 1000
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        result.cpuAfterStopPercent = (cpuSeconds() - cpuStop) / 5 * 100
        sampler.cancel()
        result.peakFootprintMB = peak
        result.footprintAfterMB = Benchmark.footprintMB()
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(result).write(to: output)
        NSApp.terminate(nil)
    }

    /// Tiles on screen without a picture yet, and all tiles on screen (the collection view also keeps items
    /// prepared outside the visible rect; those do not count).
    private static func emptyVisible(_ grid: GridCollectionView) -> (Int, Int) {
        let tiles = grid.visibleItems()
            .filter { $0.view.frame.intersects(grid.visibleRect) }
            .compactMap { ($0 as? ThumbnailItem)?.tile }
        return (tiles.filter { $0.image == nil }.count, tiles.count)
    }

    private static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
            + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
    }

    private static func gridScrollView() -> NSScrollView? {
        func search(_ view: NSView) -> NSScrollView? {
            if let scrollView = view as? NSScrollView, scrollView.documentView is GridCollectionView {
                return scrollView
            }
            return view.subviews.lazy.compactMap(search).first
        }
        return DeveloperHooks.mainWindow?.contentView.flatMap(search)
    }
}
