import AppKit
import Foundation

/// Peaks of a waveform in -1…1, one pair per bucket across the whole duration (`JGScrubber`'s audio style).
public struct JGWaveformPeaks: Equatable, Sendable {
    public let lows: [Float]
    public let highs: [Float]

    public init(lows: [Float], highs: [Float]) {
        self.lows = lows
        self.highs = highs
    }
}

/// Finer peaks for part of the timeline (`range`, in seconds), drawn instead of the whole-file peaks while the
/// scrubber is zoomed into that part.
public struct JGWaveformDetail: Equatable, Sendable {
    public let range: ClosedRange<Double>
    public let peaks: JGWaveformPeaks

    public init(range: ClosedRange<Double>, peaks: JGWaveformPeaks) {
        self.range = range
        self.peaks = peaks
    }
}

/// An end of a selected segment.
public enum JGSegmentEdge: Sendable {
    case start, end
}

/// A time pushed straight to scrubbers, bypassing SwiftUI: a playhead may move many times a second, and a
/// SwiftUI update for each would cost far more than moving its layer.
@MainActor
public final class JGLiveTime {
    public var seconds: Double = 0 {
        didSet {
            for view in views.allObjects {
                view.time = seconds
            }
        }
    }

    /// Playback speed while playing, 0 while paused: between time reports the playheads move on by themselves.
    public var rate: Double = 0 {
        didSet {
            for view in views.allObjects {
                view.playbackRate = rate
            }
        }
    }

    /// The scrubbers showing this time (the preview pane and Quick Preview can show it at once); held weakly.
    private let views = NSHashTable<ScrubberView>.weakObjects()

    public init() {}

    func attach(_ view: ScrubberView) {
        views.add(view)
    }
}
