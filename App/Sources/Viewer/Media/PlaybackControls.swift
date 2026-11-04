import JGDesign
import JGModel
import JGPlayback
import JGSettings
import SwiftUI

/// The controls row of the video and audio viewers (docs/DESIGN.md §8): previous, play, next, time, then speed,
/// volume, loop, play next and (video) full screen.
struct PlaybackControls: View {
    let model: MediaViewerModel
    let isFullScreen: Bool
    let onToggleFullScreen: () -> Void

    private var playback: PlaybackController {
        model.playback
    }

    var body: some View {
        HStack(spacing: JGSpacing.xxs) {
            ViewerIconButton(symbol: "backward.end.fill", label: Text("Previous", comment: "Player: previous file")) {
                model.perform(.previous)
            }
            ViewerIconButton(
                symbol: playback.isPlaying ? "pause.fill" : "play.fill",
                label: playback.isPlaying ? Text("Pause", comment: "Player") : Text("Play", comment: "Player")
            ) {
                model.perform(.togglePlay)
            }
            .disabled(model.isFailed)
            ViewerIconButton(symbol: "forward.end.fill", label: Text("Next", comment: "Player: next file")) {
                model.perform(.next)
            }
            .disabled(!playback.queue.hasNext)
            PlaybackTimeLabel(playback: playback)
                .padding(.leading, JGSpacing.xs)
            Spacer(minLength: JGSpacing.m)
            SegmentControls(model: model)
            if model.kind == .audio {
                MusicButton(model: model)
            }
            SpeedMenu(tuning: model.tuning, kind: model.kind)
            VolumeControl(tuning: model.tuning)
            ViewerIconButton(symbol: "repeat", label: Text("Loop", comment: "Player: repeat the current file"), isOn: playback.loops) {
                model.toggleLoop()
            }
            ViewerIconButton(
                symbol: "text.line.last.and.arrowtriangle.forward",
                label: Text("Play Next", comment: "Player: continue with the next file at the end"),
                isOn: playback.autoAdvance
            ) {
                model.togglePlaysNext()
            }
            if model.kind == .video {
                ViewerIconButton(
                    symbol: "camera",
                    label: Text("Save Frame", comment: "Player: saves the video frame on screen as a picture")
                ) {
                    model.saveFrame(copying: false)
                }
                .contextMenu {
                    Button {
                        model.saveFrame(copying: true)
                    } label: {
                        Text("Copy Frame", comment: "Player: copies the video frame on screen")
                    }
                }
                ViewerIconButton(
                    symbol: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    label: isFullScreen
                        ? Text("Exit Full Screen", comment: "Player: leaves full screen")
                        : Text("Full Screen", comment: "Player: toggles full screen"),
                    action: onToggleFullScreen
                )
            }
        }
    }
}

/// Segment selection (D-73): the mode button; while it is on, the segment's ends, the fades toggle (audio) and the
/// export button to drag out.
struct SegmentControls: View {
    let model: MediaViewerModel

    var body: some View {
        HStack(spacing: JGSpacing.xxs) {
            if let segment = model.segment {
                Text(verbatim: Self.label(segment))
                    .jgTextStyle(.mono)
                    .foregroundStyle(JGColor.accentText)
                    .monospacedDigit()
                    .padding(.trailing, JGSpacing.xxs)
                if model.kind == .audio {
                    ViewerGlyphButton(
                        label: Text("Fade the Ends", comment: "Player: short fades at both ends of an exported audio segment"),
                        isOn: model.tuning.preferences.segmentFades, action: model.toggleSegmentFades
                    ) {
                        FadeEdgesIcon()
                    }
                }
            }
            // Always there (D-107): without a segment it saves the whole file.
            SegmentExportButton(request: model.segment == nil ? model.wholeExport : model.segmentExport, isWhole: model.segment == nil)
                .frame(width: JGMetrics.controlHeight, height: JGMetrics.controlHeight)
            ViewerIconButton(
                symbol: "timeline.selection",
                label: Text("Select a Segment", comment: "Player: mode for choosing a part of the file to export"),
                isOn: model.isSelectingSegment, action: model.toggleSegmentMode
            )
            .disabled(model.isFailed || (model.playback.duration ?? 0) <= 0)
        }
    }

    /// `1:02.3–1:15.0`
    static func label(_ segment: ClosedRange<Double>) -> String {
        let start = DurationFormat.tenths(segment.lowerBound) ?? ""
        let end = DurationFormat.tenths(segment.upperBound) ?? ""
        return "\(start)–\(end)"
    }
}

/// Mute button and volume ruler of the players and Quick Preview; the volume is remembered (`PlaybackTuning`).
struct VolumeControl: View {
    let tuning: PlaybackTuning

    private var playback: PlaybackController {
        tuning.playback
    }

    var body: some View {
        HStack(spacing: 0) {
            ViewerIconButton(
                symbol: Self.speakerSymbol(volume: playback.isMuted ? 0 : playback.volume),
                label: playback.isMuted ? Text("Unmute", comment: "Player") : Text("Mute", comment: "Player")
            ) {
                playback.isMuted.toggle()
            }
            JGSlider(
                value: Binding(
                    get: { Double(playback.isMuted ? 0 : playback.volume) * 100 },
                    set: { tuning.setVolume(Float($0 / 100)) }
                ),
                in: 0 ... 100, step: 10,
                accessibilityLabel: String(localized: "Volume", comment: "Player volume slider"),
                focusesOnClick: false
            )
            .frame(width: JGMetrics.volumeSliderWidth)
        }
    }

    static func speakerSymbol(volume: Float) -> String {
        switch volume {
        case ...0: "speaker.slash.fill"
        case ..<0.34: "speaker.wave.1.fill"
        case ..<0.67: "speaker.wave.2.fill"
        default: "speaker.wave.3.fill"
        }
    }
}

/// Elapsed / total time in mono; its own view, updated once a second (`currentTime` changes with the shown second).
struct PlaybackTimeLabel: View {
    let playback: PlaybackController

    var body: some View {
        let elapsed = DurationFormat.positional(playback.currentTime) ?? "0:00"
        let total = playback.duration.flatMap(DurationFormat.positional) ?? "–:––"
        Text(verbatim: "\(elapsed) / \(total)")
            .jgTextStyle(.mono)
            .foregroundStyle(JGColor.textSecondary)
            .monospacedDigit()
            // One line always: squeezed, it broke a character per line (D-112).
            .lineLimit(1)
            .fixedSize()
            .accessibilityLabel(Text(verbatim: "\(elapsed) / \(total)"))
    }
}

/// The scrubber. Time is observed only while `isObserving` (the scrubber is visible) and the view is on screen,
/// so a hidden scrubber costs no periodic callbacks; the playhead follows `liveTime` without SwiftUI updates.
struct PlaybackScrubber: View {
    let playback: PlaybackController
    let liveTime: JGLiveTime
    var waveform: JGWaveformPeaks?
    /// The video player's own choice (D-110); nil: the audio players' (Settings → Decor).
    var style: WaveformStyle?
    let isObserving: Bool
    /// Segment selection (the viewers only): brackets, zoom and finer peaks.
    var segmentModel: MediaViewerModel?

    @State private var observes = false
    @Environment(\.appSettings) private var settings
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var reduceMotionOverride
    @State private var width: CGFloat = 0
    /// Seconds shown across the width (less than the duration when zoomed in).
    @State private var shownSeconds: Double?

    var body: some View {
        JGScrubber(
            liveTime: liveTime, duration: playback.duration ?? 0, waveform: isTimeline ? nil : waveform,
            accessibilityLabel: String(localized: "Position", comment: "Player scrubber")
        ) { seconds, isFinal in
            // Silent while dragged (D-77).
            playback.mutesWhileScrubbing = !isFinal
            playback.seek(to: seconds, precise: isFinal)
        }
        .animatesPlayhead(isObserving)
        .animatesWaveform(!(systemReduceMotion || reduceMotionOverride))
        .segment(segmentModel?.segment) { range, edge, isFinal in
            segmentModel?.setSegment(range, edge: edge, isFinal: isFinal)
        }
        .segmentMenu { segmentModel.flatMap(SegmentMenu.make) }
        .zoomable(
            segmentModel?.isSelectingSegment == true, wheelZooms: settings.wheelZoomsTimeline,
            detail: isTimeline ? nil : segmentModel?.waveformDetail
        ) { range in
            shownSeconds = range.upperBound - range.lowerBound
            if !isTimeline {
                segmentModel?.segmentWindowChanged(range)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .onAppear { observe(isObserving) }
        .onDisappear { observe(false) }
        .onChange(of: isObserving) { observe(isObserving) }
        // Updates only as often as the playhead moves a point (long songs: a few times a second).
        // The playhead moves smoothly between updates (D-77): a few a second are enough, more when zoomed in far.
        .onChange(of: UpdateKey(duration: shownSeconds ?? playback.duration, width: width, rate: playback.rate), initial: true) {
            let pointPerUpdate = playback.timeUpdateInterval(duration: shownSeconds ?? playback.duration, width: Double(width))
            playback.timeUpdateInterval = max(pointPerUpdate, PlaybackController.smoothUpdateInterval)
        }
    }

    /// Drawn as the plain ruler (Settings → Decor → Audio player, Video player).
    private var isTimeline: Bool {
        waveform != nil && (style ?? settings.waveformStyle) == .timeline
    }

    private struct UpdateKey: Equatable {
        let duration: Double?
        let width: CGFloat
        let rate: Float
    }

    /// Keeps `beginTimeUpdates` / `endTimeUpdates` balanced.
    private func observe(_ isOn: Bool) {
        guard isOn != observes else { return }
        observes = isOn
        if isOn {
            playback.beginTimeUpdates()
        } else {
            playback.endTimeUpdates()
        }
    }
}

/// Speed presets and pitch preservation; the label shows the current speed (`1.0×`).
struct SpeedMenu: View {
    let tuning: PlaybackTuning
    let kind: MediaKind

    private var playback: PlaybackController {
        tuning.playback
    }

    var body: some View {
        // The menu button sizes itself to its title and ignores views hidden in its label, so a hidden `1.25×` beside
        // it holds the width at any speed and nothing next to it moves (D-111).
        ZStack {
            Text(verbatim: Self.label(1.25))
                .font(.system(size: JGTextStyle.heading.size, weight: .semibold))
                .hidden()
                .accessibilityHidden(true)
            menu
        }
    }

    private var menu: some View {
        Menu {
            Picker(selection: Binding(get: { playback.rate }, set: { tuning.setRate($0, for: kind) })) {
                ForEach(Self.choices(current: playback.rate), id: \.self) { rate in
                    Text(verbatim: Self.label(rate)).tag(rate)
                }
            } label: {
                Text("Speed", comment: "Player speed menu")
            }
            .pickerStyle(.inline)
            Divider()
            Toggle(isOn: Binding(get: { playback.preservesPitch }, set: { tuning.setPreservesPitch($0) })) {
                Text("Keep Pitch", comment: "Player: keep the pitch when the speed changes")
            }
            if kind == .audio {
                targetPitch
            }
        } label: {
            Text(verbatim: Self.label(playback.rate))
                .jgTextStyle(.mono)
                .foregroundStyle(JGColor.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Text("Speed", comment: "Player speed menu"))
        .accessibilityLabel(Text("Speed", comment: "Player speed menu"))
        .accessibilityValue(Text(verbatim: Self.label(playback.rate)))
    }

    /// The speeds that land on a pitch, in semitones from the song's own, for this song only (D-106; audio only).
    private var targetPitch: some View {
        Menu {
            ForEach((-PlaybackTarget.limit ... PlaybackTarget.limit).reversed(), id: \.self) { semitones in
                Toggle(isOn: Binding(
                    get: { tuning.isTargeted && abs(tuning.heardSemitones - Double(semitones)) < 0.02 },
                    set: { _ in tuning.setTargetRate(PlaybackTarget.rate(semitones: Double(semitones)), for: kind) }
                )) {
                    Text(verbatim: Self.pitchLabel(semitones))
                }
            }
        } label: {
            Text("Target Pitch", comment: "Key and tempo panel: the pitch to play the song at")
        }
    }

    /// `+2 · 1.12×`
    static func pitchLabel(_ semitones: Int) -> String {
        "\(PlaybackTarget.label(Double(semitones))) · \(label(Float(PlaybackTarget.rate(semitones: Double(semitones)))))"
    }

    /// The presets, plus the current speed when `[` `]` set one in between.
    static func choices(current: Float) -> [Float] {
        PlaybackSpeed.presets.contains(current) ? PlaybackSpeed.presets : (PlaybackSpeed.presets + [current]).sorted()
    }

    /// `1.0×`, `1.25×`, `0.5×` in the user's number format.
    static func label(_ rate: Float) -> String {
        Double(rate).formatted(.number.precision(.fractionLength(1 ... 2))) + "×"
    }
}
