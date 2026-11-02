import AppKit
import Foundation
import os

/// Grid and launch benchmark (`scripts/bench.sh`): launch milestones, folder switches, a constant-speed scroll
/// counting late frames, memory footprint and idle CPU. Informational (DECISIONS D-42): writes JSON plus a
/// short summary marking each number ok / near (within 1.5× of its target) / over.
@MainActor
enum Benchmark {
    struct Result: Codable {
        var items = 0
        var launchInteractiveMs: Double?
        var launchFirstTileMs: Double?
        var scrollSeconds = 0.0
        var scrollPointsPerSecond = 0.0
        var frames = 0
        var lateFrames = 0
        var worstFrameMs = 0.0
        /// Seconds into the scroll at which late frames happened, and their length in ms.
        var lateFrameAt: [String] = []
        var refreshRateHz = 0.0
        /// Folder switch → first thumbnail visible: a year folder of the synthetic library (≈18k files with
        /// subfolders, first screen in cache.sqlite) and a folder whose thumbnails were never generated.
        var openLargeFolderMs: Double?
        var openLargeFolderItems = 0
        var openUncachedFolderMs: Double?
        var footprintBeforeScrollMB = 0.0
        var footprintMB = 0.0
        var idleCPUPercent = 0.0
    }

    static func run(library: LibraryModel, output: URL) async {
        var result = Result()
        result.items = library.refs.count
        // Give the first tiles of a launch up to two seconds.
        for _ in 0 ..< 20 where LaunchMetrics.firstTile == nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        if let start = LaunchMetrics.processStart {
            result.launchInteractiveMs = LaunchMetrics.interactive.map { $0.timeIntervalSince(start) * 1000 }
            result.launchFirstTileMs = LaunchMetrics.firstTile.map { $0.timeIntervalSince(start) * 1000 }
        }
        result.footprintBeforeScrollMB = footprintMB()
        try? Data().write(to: output.appendingPathExtension("ready"))
        try? await Task.sleep(for: .milliseconds(500))
        if let scrollView = gridScrollView() {
            let driver = ScrollDriver(scrollView: scrollView, pointsPerSecond: 4000)
            let scroll = await driver.run(seconds: 5)
            result.scrollSeconds = 5
            result.scrollPointsPerSecond = 4000
            result.frames = scroll.frames
            result.lateFrames = scroll.lateFrames
            result.worstFrameMs = scroll.worstFrame * 1000
            result.lateFrameAt = scroll.late.map { String(format: "%.2fs: %.0fms", $0.at, $0.length * 1000) }
            result.refreshRateHz = scroll.refreshRate
        }
        if let root = library.roots.first, let tree = library.trees[root.id] {
            if let year = tree.children?.first {
                result.openLargeFolderMs = await timeToFirstTile(library) { library.select(folderID: year.id) }
                result.openLargeFolderItems = library.refs.count
            }
            if let last = tree.children?.last?.children?.last {
                result.openUncachedFolderMs = await timeToFirstTile(library) { library.select(folderID: last.id) }
            }
            library.select(folderID: tree.id)
        }
        // Marker for external tools (footprint, vmmap) that sample the process right after scrolling.
        try? Data().write(to: output.appendingPathExtension("scrolled"))
        // Let thumbnail work finish, then measure an idle app.
        try? await Task.sleep(for: .seconds(2))
        result.footprintMB = footprintMB()
        result.idleCPUPercent = await idleCPUPercent(over: 3)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(result).write(to: output)
        try? Data(summary(result).utf8).write(to: output.deletingPathExtension().appendingPathExtension("txt"))
    }

    /// "ok" within the target, "near" within 1.5× of it, else "over" (budgets are targets, DECISIONS D-42).
    static func verdict(_ value: Double, _ target: Double) -> String {
        value <= target ? "ok" : (value <= target * 1.5 ? "near" : "over")
    }

    /// One line per metric: value, target (ARCHITECTURE §19), verdict.
    static func summary(_ result: Result) -> String {
        func line(_ name: String, _ value: Double?, _ unit: String, target: Double) -> String {
            guard let value else { return "\(name): n/a" }
            return String(format: "%@: %.0f %@ (target %.0f) %@", name, value, unit, target, verdict(value, target))
        }
        let latePercent = result.frames > 0 ? Double(result.lateFrames) / Double(result.frames) * 100 : 0
        return [
            "\(result.items) items",
            line("launch → index on screen", result.launchInteractiveMs, "ms", target: 400),
            line("launch → first thumbnails", result.launchFirstTileMs, "ms", target: 400),
            line("open large folder (\(result.openLargeFolderItems) items)", result.openLargeFolderMs, "ms", target: 100),
            line("open never-seen folder", result.openUncachedFolderMs, "ms", target: 200),
            String(
                format: "scroll: %d late of %d frames at %.0f Hz %@", result.lateFrames, result.frames, result.refreshRateHz,
                latePercent == 0 ? "ok" : (latePercent <= 2 ? "near" : "over")
            ),
            line("memory", result.footprintMB, "MB", target: 250),
            String(format: "idle CPU: %.2f %% (target 1) %@", result.idleCPUPercent, verdict(result.idleCPUPercent, 1)),
        ].joined(separator: "\n") + "\n"
    }

    /// Milliseconds from `action` (a folder switch) until a thumbnail of the new index is visible; nil after 5 s.
    private static func timeToFirstTile(_ library: LibraryModel, _ action: () -> Void) async -> Double? {
        let start = Date()
        let version = library.refsVersion
        let shown: Bool = await withCheckedContinuation { continuation in
            var resumed = false
            LaunchMetrics.onTile = {
                // Tiles of the previous folder may still appear until the new index arrives.
                guard library.refsVersion > version else { return false }
                if !resumed {
                    resumed = true
                    continuation.resume(returning: true)
                }
                return true
            }
            action()
            Task {
                try? await Task.sleep(for: .seconds(5))
                guard !resumed else { return }
                resumed = true
                LaunchMetrics.onTile = nil
                continuation.resume(returning: false)
            }
        }
        return shown ? Date().timeIntervalSince(start) * 1000 : nil
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

    /// Physical memory footprint (what Activity Monitor shows as Memory).
    static func footprintMB() -> Double {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let status = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return status == KERN_SUCCESS ? Double(info.phys_footprint) / 1_048_576 : -1
    }

    /// Process CPU time over `seconds` of wall time, in percent of one core.
    static func idleCPUPercent(over seconds: Double) async -> Double {
        func cpuSeconds() -> Double {
            var usage = rusage()
            getrusage(RUSAGE_SELF, &usage)
            let user = Double(usage.ru_utime.tv_sec) + Double(usage.ru_utime.tv_usec) / 1_000_000
            let system = Double(usage.ru_stime.tv_sec) + Double(usage.ru_stime.tv_usec) / 1_000_000
            return user + system
        }
        let before = cpuSeconds()
        try? await Task.sleep(for: .seconds(seconds))
        return (cpuSeconds() - before) / seconds * 100
    }
}

/// Scrolls a scroll view at constant speed from a display link and counts frames that arrive later than
/// 1.5 refresh intervals (a dropped frame from the app's point of view).
@MainActor
final class ScrollDriver: NSObject {
    struct Outcome {
        var frames = 0
        var lateFrames = 0
        var worstFrame = 0.0
        var refreshRate = 0.0
        var late: [(at: Double, length: Double)] = []
    }

    private let scrollView: NSScrollView
    private let pointsPerSecond: Double
    private var link: CADisplayLink?
    private var lastTimestamp: CFTimeInterval?
    private var outcome = Outcome()
    private var deadline: CFTimeInterval = 0
    private var seconds: CFTimeInterval = 0
    private var continuation: CheckedContinuation<Outcome, Never>?
    private let signposter = OSSignposter(subsystem: "jGlancer.app", category: "grid")

    init(scrollView: NSScrollView, pointsPerSecond: Double) {
        self.scrollView = scrollView
        self.pointsPerSecond = pointsPerSecond
    }

    func run(seconds: Double) async -> Outcome {
        let state = signposter.beginInterval("grid.scroll")
        defer { signposter.endInterval("grid.scroll", state) }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            self.seconds = seconds
            deadline = CACurrentMediaTime() + seconds
            let link = scrollView.displayLink(target: self, selector: #selector(tick(_:)))
            link.add(to: .main, forMode: .common)
            self.link = link
        }
    }

    @objc private func tick(_ link: CADisplayLink) {
        let interval = link.targetTimestamp - link.timestamp
        outcome.refreshRate = interval > 0 ? (1 / interval).rounded() : 0
        if let lastTimestamp {
            let delta = link.timestamp - lastTimestamp
            outcome.frames += 1
            outcome.worstFrame = max(outcome.worstFrame, delta)
            if delta > interval * 1.5 {
                outcome.lateFrames += 1
                outcome.late.append((at: link.timestamp - (deadline - seconds), length: delta))
            }
            let clip = scrollView.contentView
            let maxY = max(0, (scrollView.documentView?.frame.height ?? 0) - clip.bounds.height)
            let next = min(maxY, clip.bounds.origin.y + pointsPerSecond * delta)
            clip.scroll(to: NSPoint(x: 0, y: next))
            scrollView.reflectScrolledClipView(clip)
        }
        lastTimestamp = link.timestamp
        if link.timestamp >= deadline {
            link.invalidate()
            continuation?.resume(returning: outcome)
            continuation = nil
        }
    }
}

/// Viewer benchmark (PLAN Phase 3): warm open of a library photo and of a file outside the library, then flipping
/// with the pager's preload (one photo per 300 ms) and rapid flipping (one per 33 ms, like a held arrow key).
/// Targets (ARCHITECTURE §19): next photo ≤ 50 ms, open from Finder (warm) ≤ 150 ms. Informational (D-42).
@MainActor
enum ViewerBenchmark {
    struct Result: Codable {
        var openLibraryPhotoMs: Double?
        var openOutsideFileMs: Double?
        var nextMedianMs: Double?
        var nextWorstMs: Double?
        var rapidSharpPercent = 0.0
        var footprintMB = 0.0
    }

    static func run(appModel: AppModel, libraryFile: URL, outsideFile: URL?, output: URL) async {
        var result = Result()
        result.openLibraryPhotoMs = await timeToSharpPicture(appModel) { await appModel.open([libraryFile]) }
        if let viewer = appModel.photoViewer {
            try? await Task.sleep(for: .seconds(1))
            var latencies: [Double] = []
            for _ in 0 ..< 30 where viewer.index < viewer.count - 1 {
                viewer.move(by: 1)
                if let latency = await waitForNavigation(viewer) {
                    latencies.append(latency)
                }
                try? await Task.sleep(for: .milliseconds(300))
            }
            latencies.sort()
            result.nextMedianMs = latencies.isEmpty ? nil : latencies[latencies.count / 2]
            result.nextWorstMs = latencies.last
            var sharp = 0
            var steps = 0
            for _ in 0 ..< 20 where viewer.index < viewer.count - 1 {
                viewer.move(by: 1)
                try? await Task.sleep(for: .milliseconds(33))
                steps += 1
                if let picture = viewer.picture, !picture.isPlaceholder {
                    sharp += 1
                }
            }
            result.rapidSharpPercent = steps > 0 ? Double(sharp) / Double(steps) * 100 : 0
            result.footprintMB = Benchmark.footprintMB()
        }
        if let outsideFile {
            appModel.closeViewer()
            try? await Task.sleep(for: .milliseconds(500))
            result.openOutsideFileMs = await timeToSharpPicture(appModel) { await appModel.open([outsideFile]) }
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try? encoder.encode(result).write(to: output)
        try? Data(summary(result).utf8).write(to: output.deletingPathExtension().appendingPathExtension("txt"))
    }

    private static func timeToSharpPicture(_ appModel: AppModel, _ action: () async -> Void) async -> Double? {
        let start = Date()
        await action()
        while Date().timeIntervalSince(start) < 5 {
            if let picture = appModel.photoViewer?.picture, !picture.isPlaceholder {
                return Date().timeIntervalSince(start) * 1000
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return nil
    }

    private static func waitForNavigation(_ viewer: PhotoViewerModel) async -> Double? {
        let start = Date()
        while Date().timeIntervalSince(start) < 2 {
            if let latency = viewer.lastNavigationMilliseconds {
                return latency
            }
            try? await Task.sleep(for: .milliseconds(1))
        }
        return nil
    }

    static func summary(_ result: Result) -> String {
        func line(_ name: String, _ value: Double?, target: Double) -> String {
            guard let value else { return "\(name): n/a" }
            return String(format: "%@: %.0f ms (target %.0f) %@", name, value, target, Benchmark.verdict(value, target))
        }
        return [
            line("open library photo (warm)", result.openLibraryPhotoMs, target: 150),
            line("open file from outside the library (warm)", result.openOutsideFileMs, target: 150),
            line("next photo, preloaded (median)", result.nextMedianMs, target: 50),
            line("next photo, preloaded (worst)", result.nextWorstMs, target: 50),
            String(format: "rapid flipping: %.0f %% of steps sharp", result.rapidSharpPercent),
            String(format: "memory: %.0f MB (target 500) %@", result.footprintMB, Benchmark.verdict(result.footprintMB, 500)),
        ].joined(separator: "\n") + "\n"
    }
}
