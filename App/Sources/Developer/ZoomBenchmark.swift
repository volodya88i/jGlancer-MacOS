import AppKit
import Foundation

/// `-JGZoomBenchmark <out.json>` (with `-JGAddFolder <photos>`): a ruler drag on the grid's tile size, 60 changes a
/// second from the current size up by 200 points and back over 3 s. Records the gaps between ticks (a late tick is a
/// main thread busy past a frame), the CPU, and the peak memory. Then quits.
@MainActor
enum ZoomBenchmark {
    struct Result: Codable {
        var items = 0
        var ticks = 0
        var lateTicks = 0
        var averageGapMs = 0.0
        var worstGapMs = 0.0
        var cpuPercent = 0.0
        var peakFootprintMB = 0.0
        /// The first tile on screen, as drawn: its biggest move and size change between two ticks, and how
        /// many ticks it jumped by more than 12 points.
        var worstTileMovePt = 0.0
        var worstTileResizePt = 0.0
        var tileJumps = 0
        /// Tiles on screen once the drag settled (0: the grid went blank).
        var visibleAfter = 0
    }

    static func run(library: LibraryModel, output: URL) async {
        try? await Task.sleep(for: .seconds(2))
        var result = Result()
        result.items = library.refs.count
        var peak = Benchmark.footprintMB()
        let sampler = Task {
            while !Task.isCancelled {
                peak = max(peak, Benchmark.footprintMB())
                try? await Task.sleep(for: .milliseconds(50))
            }
        }
        let start = library.state.tileSide
        let cpuBefore = cpuSeconds()
        let began = CACurrentMediaTime()
        var last = began
        var gaps: [Double] = []
        // -JGZoomStep <points>: a fast drag takes big steps (D-112); the default is a slow one, about 2 points a tick.
        let stepPoints = DeveloperHooks.defaults.double(forKey: "JGZoomStep")
        let ticks = stepPoints > 0 ? max(2, Int(400 / stepPoints)) : 180
        let grid = DeveloperHooks.mainWindow?.contentView.flatMap(findGrid)
        let tracked = grid.flatMap(middleTile)
        var lastFrame = tracked.flatMap { drawnFrame(of: $0, in: grid) }
        for tick in 0 ... ticks {
            // Up and back down: a triangle over the drag.
            let phase = Double(tick) / Double(ticks)
            library.setTileSide(start + 200 * (phase < 0.5 ? phase * 2 : (1 - phase) * 2))
            try? await Task.sleep(for: .milliseconds(16))
            let now = CACurrentMediaTime()
            gaps.append((now - last) * 1000)
            last = now
            if let tracked, let frame = drawnFrame(of: tracked, in: grid), let previous = lastFrame {
                let move = hypot(frame.minX - previous.minX, frame.minY - previous.minY)
                let resize = abs(frame.width - previous.width)
                result.worstTileMovePt = max(result.worstTileMovePt, move)
                result.worstTileResizePt = max(result.worstTileResizePt, resize)
                result.tileJumps += move > 12 || resize > 12 ? 1 : 0
                lastFrame = frame
            }
        }
        let seconds = CACurrentMediaTime() - began
        result.cpuPercent = (cpuSeconds() - cpuBefore) / seconds * 100
        sampler.cancel()
        result.ticks = gaps.count
        result.lateTicks = gaps.filter { $0 > 25 }.count
        result.averageGapMs = gaps.reduce(0, +) / Double(max(gaps.count, 1))
        result.worstGapMs = gaps.max() ?? 0
        result.peakFootprintMB = peak
        try? await Task.sleep(for: .seconds(1))
        result.visibleAfter = grid?.visibleItems().count ?? 0
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(result).write(to: output)
    }

    private static func findGrid(_ view: NSView) -> GridCollectionView? {
        if let grid = view as? GridCollectionView {
            return grid
        }
        return view.subviews.lazy.compactMap(findGrid).first
    }

    /// The asset of the first tile on screen: the size change keeps it in place, so it stays visible.
    private static func middleTile(_ grid: GridCollectionView) -> Int64? {
        grid.visibleItems().compactMap { $0 as? ThumbnailItem }
            .filter { $0.view.frame.minY >= grid.visibleRect.minY }
            .min { ($0.view.frame.minY, $0.view.frame.minX) < ($1.view.frame.minY, $1.view.frame.minX) }?.assetID
    }

    /// Where the tile of `id` is drawn on screen (a running glide included), relative to the visible rect.
    private static func drawnFrame(of id: Int64, in grid: GridCollectionView?) -> CGRect? {
        guard let grid, let item = grid.visibleItems().compactMap({ $0 as? ThumbnailItem }).first(where: { $0.assetID == id }),
              let layer = item.view.layer
        else { return nil }
        let frame = layer.presentation()?.frame ?? layer.frame
        return frame.offsetBy(dx: -grid.visibleRect.minX, dy: -grid.visibleRect.minY)
    }

    private static func cpuSeconds() -> Double {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        return Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
            + Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
    }
}
