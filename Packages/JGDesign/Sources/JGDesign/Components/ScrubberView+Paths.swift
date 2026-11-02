import CoreGraphics

/// The track shapes of `ScrubberView`: the slider's rounded track, or a waveform for the whole timeline or a zoomed
/// window of it.
extension ScrubberView {
    /// The plain slider's rounded track from the left edge, `width` long (at least round), across the middle.
    static func sliderPath(width: CGFloat, in bounds: CGRect) -> CGPath {
        let thickness = JGMetrics.sliderThickness
        return CGPath(
            roundedRect: CGRect(x: 0, y: bounds.midY - thickness / 2, width: max(width, thickness), height: thickness),
            cornerWidth: thickness / 2, cornerHeight: thickness / 2, transform: nil
        )
    }

    /// A filled outline: highs along the top, lows back along the bottom, one column per point, scaled so the
    /// loudest peak of the whole file reaches the edges (or `height` of them: the narrow style). Zoomed in, `detail`
    /// supplies finer peaks where it covers the window.
    static func waveformPath(
        _ peaks: JGWaveformPeaks, detail: JGWaveformDetail? = nil, duration: Double = 0, visible: ScrubberWindow? = nil,
        height: CGFloat = 1, in bounds: CGRect
    ) -> CGPath {
        let columns = waveColumns(peaks, detail: detail, duration: duration, visible: visible, count: Int(bounds.width.rounded(.down)))
        return wavePath(columns, height: height, in: bounds)
    }

    /// The waveform as columns, one per point: highs and lows in -1…1 of the loudest peak of the file.
    static func waveColumns(
        _ peaks: JGWaveformPeaks, detail: JGWaveformDetail?, duration: Double, visible: ScrubberWindow?, count columns: Int
    ) -> WaveColumns {
        let whole = PeakSource(peaks: peaks, range: 0 ... max(duration, 1))
        guard !peaks.lows.isEmpty, !peaks.highs.isEmpty, columns > 1 else { return WaveColumns(tops: [], bottoms: []) }
        let shown = visible ?? ScrubberWindow(duration: max(duration, 1))
        let fine = detail.map { PeakSource(peaks: $0.peaks, range: $0.range) }
        let loudest = CGFloat(max(peaks.highs.max() ?? 0, -(peaks.lows.min() ?? 0), 0.05))
        var tops: [CGFloat] = []
        var bottoms: [CGFloat] = []
        tops.reserveCapacity(columns)
        bottoms.reserveCapacity(columns)
        for column in 0 ..< columns {
            let from = shown.start + Double(column) / Double(columns) * shown.length
            let to = shown.start + Double(column + 1) / Double(columns) * shown.length
            let source = fine.flatMap { $0.covers(from, to) && $0.bucketSeconds < whole.bucketSeconds ? $0 : nil } ?? whole
            let (low, high) = source.peak(from: from, to: to)
            tops.append(CGFloat(high) / loudest)
            bottoms.append(CGFloat(low) / loudest)
        }
        return WaveColumns(tops: tops, bottoms: bottoms)
    }

    /// The outline of `columns` across `bounds`; at least a hairline, so silence still reads as a line.
    static func wavePath(_ columns: WaveColumns, height: CGFloat = 1, in bounds: CGRect) -> CGPath {
        let path = CGMutablePath()
        let count = min(columns.tops.count, columns.bottoms.count)
        guard count > 1 else { return path }
        let middle = bounds.midY
        let half = bounds.height / 2
        let scale = half * height
        let floor = JGMetrics.outlineWidth / 2
        let step = bounds.width / CGFloat(count)
        path.move(to: CGPoint(x: 0, y: middle - min(max(columns.tops[0] * scale, floor), half)))
        for column in 1 ..< count {
            path.addLine(to: CGPoint(x: CGFloat(column) * step, y: middle - min(max(columns.tops[column] * scale, floor), half)))
        }
        for column in (0 ..< count).reversed() {
            path.addLine(to: CGPoint(x: CGFloat(column) * step, y: middle - max(min(columns.bottoms[column] * scale, -floor), -half)))
        }
        path.closeSubpath()
        return path
    }
}

/// A waveform as drawn: per-point highs and lows in -1…1.
struct WaveColumns: Equatable {
    var tops: [CGFloat]
    var bottoms: [CGFloat]
}

/// Peaks spread evenly over a time range.
private struct PeakSource {
    let peaks: JGWaveformPeaks
    let range: ClosedRange<Double>

    var count: Int {
        min(peaks.lows.count, peaks.highs.count)
    }

    var bucketSeconds: Double {
        (range.upperBound - range.lowerBound) / Double(max(count, 1))
    }

    func covers(_ from: Double, _ to: Double) -> Bool {
        from >= range.lowerBound && to <= range.upperBound
    }

    /// The lowest and highest sample between `from` and `to` (at least the one bucket under `from`).
    func peak(from: Double, to: Double) -> (Float, Float) {
        let length = range.upperBound - range.lowerBound
        guard !peaks.lows.isEmpty, !peaks.highs.isEmpty, length > 0 else { return (0, 0) }
        let first = min(max(Int(((from - range.lowerBound) / length * Double(count)).rounded(.down)), 0), count - 1)
        let last = min(max(Int(((to - range.lowerBound) / length * Double(count)).rounded(.up)), first + 1), count)
        return (peaks.lows[first ..< last].min() ?? 0, peaks.highs[first ..< last].max() ?? 0)
    }
}
