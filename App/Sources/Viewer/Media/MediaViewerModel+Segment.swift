import AppKit
import JGDesign
import JGPlayback

/// Segment selection (D-73): accent brackets on the scrubber choose a part of the current file, which the export
/// button drags out as a new file. While it is on the timeline zooms; audio loads finer peaks for the shown part.
extension MediaViewerModel {
    /// Buckets of the finer peaks for a zoomed-in waveform (about two per point of a wide player).
    static let detailBuckets = 2048
    /// A new segment: a tenth of the file from the playhead, 1…30 s.
    static let defaultSegmentFraction = 0.1
    static let defaultSegmentRange = 1.0 ... 30.0

    var isSelectingSegment: Bool {
        segment != nil
    }

    /// Whether the current file can be cut (not Matroska).
    var canExportSegment: Bool {
        current.map { SegmentExporter.canExport($0.url, kind: kind) } ?? false
    }

    func toggleSegmentMode() {
        if isSelectingSegment {
            endSegmentMode()
        } else {
            startSegmentMode()
        }
    }

    private func startSegmentMode() {
        guard let duration = playback.duration, duration > 0 else { return }
        let length = min(
            min(max(duration * Self.defaultSegmentFraction, Self.defaultSegmentRange.lowerBound), Self.defaultSegmentRange.upperBound),
            duration
        )
        let start = min(max(playback.currentTime, 0), duration - length)
        segment = start ... start + length
        playback.stopTime = start + length
    }

    /// Leaves the mode (also when the file changes or the viewer closes).
    func endSegmentMode() {
        segment = nil
        playback.stopTime = nil
        detailTask?.cancel()
        detailTask = nil
        waveformDetail = nil
    }

    /// A bracket was dragged (D-74, D-77): the playhead jumps onto the start bracket (silent while dragged), and onto
    /// the end bracket for video, where the frame under it shows (with sound); ⌥ keeps it where it is. Playback
    /// stops at the end bracket.
    func setSegment(_ range: ClosedRange<Double>, edge: JGSegmentEdge, isFinal: Bool) {
        segment = range
        playback.stopTime = range.upperBound
        let keepsPlayhead = NSEvent.modifierFlags.contains(.option)
        guard !keepsPlayhead, edge == .start || kind == .video else {
            playback.mutesWhileScrubbing = false
            return
        }
        playback.mutesWhileScrubbing = edge == .start && !isFinal
        playback.seek(to: edge == .start ? range.lowerBound : range.upperBound, precise: isFinal)
    }

    /// Play / pause; stopped at the segment's end, Play starts again from its start.
    func togglePlayInSegment() {
        if let segment, !playback.isPlaying, abs(playback.currentTime - segment.upperBound) < Self.endTolerance {
            playback.seek(to: segment.lowerBound, precise: true)
            playback.play()
        } else {
            playback.togglePlayPause()
        }
    }

    /// How near the end bracket the playhead counts as stopped there, in seconds.
    static let endTolerance = 0.1

    /// The scrubber shows `range`: zoomed into audio, finer peaks of it (and as much again on each side, for
    /// scrolling) load after a short pause.
    func segmentWindowChanged(_ range: ClosedRange<Double>) {
        detailTask?.cancel()
        guard waveform != nil, let item = current, let duration = playback.duration,
              range.upperBound - range.lowerBound < duration * 0.5
        else {
            waveformDetail = nil
            return
        }
        if let detail = waveformDetail, detail.range.lowerBound <= range.lowerBound, detail.range.upperBound >= range.upperBound,
           detail.range.upperBound - detail.range.lowerBound <= (range.upperBound - range.lowerBound) * 4
        {
            return
        }
        let length = range.upperBound - range.lowerBound
        let wanted = max(range.lowerBound - length, 0) ... min(range.upperBound + length, duration)
        detailTask = Task { [waveforms] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            let detail = await waveforms.detail(for: item.url, range: wanted, bucketCount: Self.detailBuckets * 3)
            guard !Task.isCancelled, current == item, let detail else { return }
            waveformDetail = JGWaveformDetail(range: detail.range, peaks: JGWaveformPeaks(lows: detail.lows, highs: detail.highs))
        }
    }

    /// What the export button saves: the segment, with the speed, Keep Pitch and fades for audio.
    var segmentExport: SegmentExportRequest? {
        guard let segment, let item = current, canExportSegment else { return nil }
        var request = SegmentExportRequest(source: item.url, kind: kind, range: segment)
        request.isExact = kind == .video && segmentCutsExactly
        if kind == .audio {
            request.rate = playback.rate
            request.preservesPitch = playback.preservesPitch
            request.fades = tuning.preferences.segmentFades
            request.keepsAudioFormat = segmentKeepsAudioFormat
        }
        return request
    }

    /// What the export button saves without a segment (D-107): the whole file, audio at the speed and Keep Pitch it
    /// plays with (no fades), video copied unchanged.
    var wholeExport: SegmentExportRequest? {
        guard let item = current, let duration = playback.duration, duration > 0,
              SegmentExporter.canExportWhole(item.url, kind: kind)
        else { return nil }
        var request = SegmentExportRequest.whole(item.url, kind: kind, duration: duration)
        if kind == .audio {
            request.rate = playback.rate
            request.preservesPitch = playback.preservesPitch
            request.keepsAudioFormat = segmentKeepsAudioFormat
        }
        return request
    }

    func toggleSegmentFades() {
        tuning.setSegmentFades(!tuning.preferences.segmentFades)
    }
}
