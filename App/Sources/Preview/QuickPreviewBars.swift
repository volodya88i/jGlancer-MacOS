import JGDesign
import JGPlayback
import SwiftUI

/// Quick Preview's name row (WIN-062…069): the file's name centred on the window, kept clear of the window's own
/// buttons on the left and of Keep on Top, Open in Viewer and Get Info on the right; hidden when it does not fit, and
/// then Get Info's tooltip names the file. Over a photo or a video it lies on the picture as translucent glass.
struct QuickPreviewNameRow: View {
    let name: String
    let assetID: Int64?
    let keepsOnTop: Bool
    let onToggleOnTop: () -> Void
    let onOpenInViewer: () -> Void
    let onInfo: () -> Void
    /// Full screen, for a photo lying over the window (a video has the button in its bar).
    var onFullScreen: (() -> Void)?
    var isFullScreen = false

    @State private var rowWidth: CGFloat = 0
    @State private var nameWidth: CGFloat = 0

    private var buttonCount: CGFloat {
        onFullScreen == nil ? 3 : 4
    }

    /// The room kept free at both sides, so the name stays centred on the window.
    private var sideRoom: CGFloat {
        max(JGMetrics.windowControlsInset, buttonCount * JGMetrics.controlHeight + JGSpacing.xs)
    }

    private var nameFits: Bool {
        rowWidth == 0 || nameWidth <= rowWidth - 2 * sideRoom
    }

    var body: some View {
        ZStack {
            if nameFits {
                title
            }
            HStack(spacing: 0) {
                Spacer(minLength: 0)
                ViewerIconButton(
                    symbol: keepsOnTop ? "pin.fill" : "pin",
                    label: keepsOnTop
                        ? Text("Keep on Top: On", comment: "Quick Preview: the panel stays above every window")
                        : Text("Keep on Top: Off", comment: "Quick Preview: the panel is an ordinary window"),
                    isOn: keepsOnTop, action: onToggleOnTop
                )
                if let onFullScreen {
                    ViewerIconButton(
                        symbol: isFullScreen ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                        label: isFullScreen
                            ? Text("Exit Full Screen", comment: "Player: leaves full screen")
                            : Text("Full Screen", comment: "Player: toggles full screen"),
                        action: onFullScreen
                    )
                }
                ViewerIconButton(
                    symbol: "arrow.up.forward.square",
                    label: Text("Open in Viewer", comment: "Quick Preview: opens the file in the full viewer"),
                    action: onOpenInViewer
                )
                ViewerIconButton(
                    symbol: "info.circle", label: Text("Get Info", comment: "Action"),
                    help: nameFits ? nil : Text(verbatim: name + "\n") + Text("Get Info", comment: "Action"),
                    action: onInfo
                )
            }
        }
        .padding(.horizontal, JGSpacing.xs)
        .padding(.vertical, JGSpacing.xxs)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
        .background {
            // The name's own width, measured off screen.
            title.fixedSize().hidden()
                .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { nameWidth = $0 }
        }
    }

    private var title: some View {
        HStack(spacing: JGSpacing.xxs) {
            Text(verbatim: name)
                .jgTextStyle(.body)
                .foregroundStyle(JGColor.textPrimary)
                .lineLimit(1)
            FlagStar(assetID: assetID)
        }
    }
}

/// The video's one bar in Quick Preview (WIN-062): play / pause, the timeline, the volume and full screen over the
/// picture's bottom; no speed and no time.
struct QuickPreviewVideoBar: View {
    let preview: PreviewModel
    let fullScreen: MiniPlayer.FullScreen?

    var body: some View {
        HStack(spacing: JGSpacing.xxs) {
            ViewerIconButton(
                symbol: preview.playback.isPlaying ? "pause.fill" : "play.fill",
                label: preview.playback.isPlaying ? Text("Pause", comment: "Player") : Text("Play", comment: "Player")
            ) {
                preview.togglePlayPause()
            }
            PlaybackScrubber(playback: preview.playback, liveTime: preview.liveTime, isObserving: true)
                .frame(height: JGMetrics.controlHeightCompact)
            VolumeBubbleButton(tuning: preview.tuning)
            if let fullScreen {
                ViewerIconButton(
                    symbol: fullScreen.isOn ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
                    label: fullScreen.isOn
                        ? Text("Exit Full Screen", comment: "Player: leaves full screen")
                        : Text("Full Screen", comment: "Player: toggles full screen"),
                    action: fullScreen.toggle
                )
            }
        }
        .padding(.horizontal, JGSpacing.xs)
        .padding(.vertical, JGSpacing.xxs)
        .quickPreviewGlass()
    }
}

/// The volume icon of the video bar (WIN-064): a click mutes; hovering opens an upright slider in a small capsule
/// above it, which closes a moment after the pointer leaves both.
struct VolumeBubbleButton: View {
    let tuning: PlaybackTuning
    @State private var isOpen = false
    @State private var isOverIcon = false
    @State private var isOverBubble = false
    @State private var closing: Task<Void, Never>?

    private var playback: PlaybackController {
        tuning.playback
    }

    var body: some View {
        ViewerIconButton(
            symbol: VolumeControl.speakerSymbol(volume: playback.isMuted ? 0 : playback.volume),
            label: playback.isMuted ? Text("Unmute", comment: "Player") : Text("Mute", comment: "Player")
        ) {
            playback.isMuted.toggle()
        }
        .onHover { inside in
            isOverIcon = inside
            hoverChanged()
        }
        .overlay(alignment: .bottom) {
            if isOpen {
                VerticalVolumeSlider(value: Binding(
                    get: { Double(playback.isMuted ? 0 : playback.volume) },
                    set: { tuning.setVolume(Float($0)) }
                ))
                .padding(.horizontal, JGSpacing.xxs)
                .padding(.vertical, JGSpacing.s)
                .background(JGColor.bgRaised.opacity(JGMetrics.statusBubbleTintOpacity), in: Capsule())
                .overlay { Capsule().strokeBorder(JGColor.lineHair, lineWidth: JGMetrics.outlineWidth) }
                .onHover { inside in
                    isOverBubble = inside
                    hoverChanged()
                }
                .alignmentGuide(.bottom) { $0[.bottom] + JGMetrics.controlHeight + JGSpacing.xxs }
                .transition(.opacity)
            }
        }
    }

    private func hoverChanged() {
        closing?.cancel()
        if isOverIcon || isOverBubble {
            isOpen = true
            return
        }
        closing = Task {
            try? await Task.sleep(for: .seconds(JGMetrics.volumeBubbleCloseDelay))
            guard !Task.isCancelled else { return }
            isOpen = false
        }
    }
}

/// An upright slider (WIN-064): the 4 pt track of every slider (docs/DESIGN.md §6), filled from the bottom; up is
/// louder. Drag or click anywhere on it.
struct VerticalVolumeSlider: View {
    @Binding var value: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                Capsule().fill(JGColor.lineStrong)
                Capsule().fill(JGColor.textPrimary)
                    .frame(height: geometry.size.height * min(max(value, 0), 1))
            }
            .frame(width: JGMetrics.sliderThickness)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { drag in
                value = min(max(1 - drag.location.y / max(geometry.size.height, 1), 0), 1)
            })
        }
        .frame(width: JGMetrics.volumeBubbleWidth, height: JGMetrics.volumeBubbleHeight)
        .accessibilityElement()
        .accessibilityLabel(Text("Volume", comment: "Player volume slider"))
        .accessibilityValue(Text(verbatim: "\(Int((value * 100).rounded())) %"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: value = min(value + 0.1, 1)
            case .decrement: value = max(value - 0.1, 0)
            @unknown default: break
            }
        }
    }
}

extension View {
    /// Quick Preview's bars over a picture (WIN-063): the scrim at 60 % over a light blur of what lies beneath (plain with
    /// Reduce Transparency or Increase Contrast, as every bar).
    func quickPreviewGlass() -> some View {
        jgBarBackground(JGColor.bgBase, in: Rectangle(), tintOpacity: JGMetrics.quickPreviewBarTintOpacity)
    }
}
