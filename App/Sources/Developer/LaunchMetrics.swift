import Foundation
import os

/// Launch milestones (docs/ARCHITECTURE.md §19): signposts for Instruments and timestamps for `Benchmark`.
@MainActor
enum LaunchMetrics {
    private static let signposter = OSSignposter(subsystem: "jGlancer.app", category: "launch")
    private(set) static var interactive: Date?
    private(set) static var firstTile: Date?

    /// The asset index of the restored view is on screen.
    static func markInteractive() {
        guard interactive == nil else { return }
        interactive = Date()
        signposter.emitEvent("launch.interactive")
    }

    /// Called when a thumbnail becomes visible until it returns true (benchmarks of folder switches).
    static var onTile: (() -> Bool)?

    /// A thumbnail became visible (records the first one of the launch).
    static func markFirstTile() {
        if let onTile, onTile() {
            self.onTile = nil
        }
        guard firstTile == nil else { return }
        firstTile = Date()
        signposter.emitEvent("launch.firstTile")
    }

    /// When the process started (kernel record), for launch durations.
    static var processStart: Date? {
        var mib = [CTL_KERN, KERN_PROC, KERN_PROC_PID, getpid()]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0 else { return nil }
        let start = info.kp_proc.p_un.__p_starttime
        return Date(timeIntervalSince1970: Double(start.tv_sec) + Double(start.tv_usec) / 1_000_000)
    }
}
