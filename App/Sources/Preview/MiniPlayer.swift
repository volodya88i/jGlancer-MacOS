import JGDesign
import JGModel
import JGPlayback
import JGSettings
import SwiftUI

/// The one preview of a file, shared by the preview pane and Quick Preview (docs/ARCHITECTURE.md §17): a photo
/// fitted; a video with play, a ruler scrubber, time and speed; an audio file with cover, title and artist, a
/// waveform scrubber, play, time and speed. Clicking the video toggles pause.
struct MiniPlayer: View {
    enum Style {
        case pane
        case quickPreview

        var waveformHeight: CGFloat {
            self == .pane ? JGMetrics.miniWaveformHeight : JGMetrics.waveformHeight
        }

        var coverSide: CGFloat {
            self == .pane ? JGMetrics.miniCoverSide : JGMetrics.coverArtSide
        }
    }

    /// The full-screen button (Quick Preview: photo and video), as in the viewer.
    struct FullScreen {
        let isOn: Bool
        let toggle: () -> Void
    }

    let preview: PreviewModel
    let asset: Asset
    let style: Style
    var fullScreen: FullScreen?
    @Environment(\.appSettings) private var settings
    /// The song's tags from the shared cache, before its player has loaded (D-110).
    @State private var tags: MediaInfo?
    @State private var tagsURL: URL?

    var body: some View {
        if preview.isCloudOnly, asset.kind != .photo || preview.picture == nil {
            cloudMessage
        } else {
            switch asset.kind {
            case .photo: photo
            case .video: video
            case .audio: audio
            }
        }
    }

    /// A file kept only in the cloud (D-124): the previews do not download it; opening it does.
    private var cloudMessage: some View {
        ViewerMessage(
            symbol: "icloud.and.arrow.down",
            text: Text("In the cloud. Open it to download.", comment: "Preview of a file kept only in iCloud Drive or another cloud")
        ) {}
            .multilineTextAlignment(.center)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: Photo

    /// Quick Preview puts the full-screen button under the photo, where the video has its controls.
    @ViewBuilder
    private var photo: some View {
        if let sequence = preview.sequence {
            VStack(spacing: JGSpacing.xs) {
                photoImage
                sequenceControls(sequence)
            }
        } else if let fullScreen {
            VStack(spacing: JGSpacing.xs) {
                photoImage
                HStack {
                    Spacer()
                    fullScreenButton(fullScreen)
                }
            }
        } else {
            photoImage
        }
    }

    @ViewBuilder
    private var photoImage: some View {
        if let picture = preview.picture {
            Group {
                if let url = preview.animatedURL {
                    // A GIF or animated PNG plays (D-124).
                    AnimatedPicture(url: url, still: picture)
                        .aspectRatio(CGSize(width: picture.width, height: picture.height), contentMode: .fit)
                        .accessibilityElement()
                        .accessibilityAddTraits(.isImage)
                } else {
                    Image(decorative: picture, scale: 1)
                        .resizable()
                        .scaledToFit()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityLabel(Text(verbatim: asset.name))
        } else {
            placeholder("photo")
        }
    }

    // MARK: Sequence

    /// A folded image sequence (W-86): a ruler over its frames, play / pause and "12 / 90".
    private func sequenceControls(_ sequence: SequencePlayback) -> some View {
        VStack(spacing: JGSpacing.xs) {
            JGSlider(
                value: Binding(get: { Double(sequence.index) }, set: { preview.scrubSequence(to: Int($0.rounded())) }),
                in: 0 ... Double(max(sequence.frameCount - 1, 1)), step: 1,
                accessibilityLabel: String(localized: "Frame", comment: "Preview of an image sequence: the frame timeline"),
                focusesOnClick: false
            )
            .frame(maxWidth: .infinity)
            .frame(height: JGMetrics.controlHeightCompact)
            HStack(spacing: JGSpacing.xxs) {
                ViewerIconButton(
                    symbol: sequence.isPlaying ? "pause.fill" : "play.fill",
                    label: sequence.isPlaying ? Text("Pause", comment: "Player") : Text("Play", comment: "Player")
                ) {
                    preview.toggleSequencePlay()
                }
                Text(verbatim: "\(sequence.index + 1) / \(sequence.frameCount)")
                    .jgTextStyle(.mono)
                    .foregroundStyle(JGColor.textSecondary)
                Spacer(minLength: JGSpacing.xs)
                if let fullScreen {
                    fullScreenButton(fullScreen)
                }
            }
        }
    }

    // MARK: Video

    private var video: some View {
        VStack(spacing: JGSpacing.xs) {
            if preview.isFailed {
                failure
            } else {
                MediaSurface(
                    player: preview.playback.player, sampleLayer: preview.playback.matroskaLayer, accessibilityLabel: asset.name,
                    takesKeyboardFocus: false,
                    onCommand: { _ in }, onActivity: {}
                )
                .aspectRatio(videoAspect, contentMode: .fit)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .contentShape(Rectangle())
                .onTapGesture { preview.togglePlayPause() }
            }
            PlaybackScrubber(playback: preview.playback, liveTime: preview.liveTime, isObserving: true)
                .frame(height: JGMetrics.controlHeightCompact)
            controls
        }
    }

    private var videoAspect: CGFloat {
        if let size = preview.playback.info?.videoSize, size.height > 0 {
            return size.width / size.height
        }
        if let width = asset.width, let height = asset.height, height > 0 {
            return CGFloat(width) / CGFloat(height)
        }
        return 16 / 9
    }

    // MARK: Audio

    private var audio: some View {
        VStack(spacing: JGSpacing.s) {
            Spacer(minLength: 0)
            Group {
                if let cover = preview.cover {
                    Image(decorative: cover, scale: 1)
                        .resizable()
                        .scaledToFit()
                        .clipShape(JGShape(.medium))
                } else {
                    JGShape(.medium)
                        .fill(JGColor.bgRaised)
                        .overlay {
                            Image(systemName: "waveform")
                                .font(.system(size: JGMetrics.tileGlyphSize, weight: .light))
                                .foregroundStyle(JGColor.textTertiary)
                        }
                }
            }
            .frame(maxWidth: style.coverSide, maxHeight: style.coverSide)
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
            VStack(spacing: JGSpacing.xxs) {
                Text(verbatim: title)
                    .jgTextStyle(style == .pane ? .body : .heading)
                    .foregroundStyle(JGColor.textPrimary)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                // The line stays when empty, so nothing jumps as tags arrive (D-110).
                Text(verbatim: subtitle ?? " ")
                    .jgTextStyle(.body)
                    .foregroundStyle(JGColor.textSecondary)
                    .lineLimit(1)
                    .accessibilityHidden(subtitle == nil)
            }
            .task(id: asset.url) {
                let url = asset.url
                tags = SongTags.shared.cached(url)
                tagsURL = url
                if tags == nil {
                    tags = await SongTags.shared.load(url)
                }
            }
            Spacer(minLength: 0)
            if preview.isFailed {
                failure
            }
            PlaybackScrubber(
                playback: preview.playback, liveTime: preview.liveTime,
                waveform: preview.waveform ?? JGWaveformPeaks(lows: [0], highs: [0]), isObserving: true
            )
            .frame(height: settings.waveformStyle == .timeline ? JGMetrics.controlHeightCompact : style.waveformHeight)
            controls
        }
    }

    /// The cached tags of this file, else the player's once it has loaded this file.
    private var info: MediaInfo? {
        (tagsURL == asset.url ? tags : nil) ?? (preview.asset?.id == asset.id ? preview.playback.info : nil)
    }

    private var title: String {
        info?.title ?? (asset.name as NSString).deletingPathExtension
    }

    private var subtitle: String? {
        let parts = [info?.artist, info?.album].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    // MARK: Shared

    private var controls: some View {
        HStack(spacing: JGSpacing.xxs) {
            ViewerIconButton(
                symbol: preview.playback.isPlaying ? "pause.fill" : "play.fill",
                label: preview.playback.isPlaying ? Text("Pause", comment: "Player") : Text("Play", comment: "Player")
            ) {
                preview.togglePlayPause()
            }
            .disabled(preview.isFailed)
            PlaybackTimeLabel(playback: preview.playback)
            Spacer(minLength: JGSpacing.xs)
            SpeedMenu(tuning: preview.tuning, kind: asset.kind)
            // Quick Preview has room for the volume; the side pane does not.
            if style == .quickPreview {
                VolumeControl(tuning: preview.tuning)
            }
            if let fullScreen, asset.kind == .video {
                fullScreenButton(fullScreen)
            }
        }
    }

    private func fullScreenButton(_ fullScreen: FullScreen) -> some View {
        ViewerIconButton(
            symbol: fullScreen.isOn ? "arrow.down.right.and.arrow.up.left" : "arrow.up.left.and.arrow.down.right",
            label: fullScreen.isOn
                ? Text("Exit Full Screen", comment: "Player: leaves full screen")
                : Text("Full Screen", comment: "Player: toggles full screen"),
            action: fullScreen.toggle
        )
    }

    private var failure: some View {
        ViewerMessage(
            symbol: asset.kind == .video ? "film" : "waveform",
            text: Text("Can't play this file.", comment: "Player state for an unsupported or damaged file")
        ) {}
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func placeholder(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: JGMetrics.tileGlyphSize, weight: .light))
            .foregroundStyle(JGColor.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .accessibilityHidden(true)
    }
}

/// One line of facts about a file in mono (docs/DESIGN.md §8): dimensions or duration, size, date.
enum PreviewFacts {
    static func line(for asset: Asset) -> String {
        var parts: [String] = []
        if let duration = asset.duration, let text = DurationFormat.positional(duration) {
            parts.append(text)
        }
        if let width = asset.width, let height = asset.height {
            parts.append("\(width) × \(height)")
        }
        parts.append(ByteCountFormatter.string(fromByteCount: asset.size, countStyle: .file))
        return parts.joined(separator: " · ")
    }

    static func date(for asset: Asset) -> String {
        (asset.capturedAt ?? asset.modifiedAt).formatted(date: .abbreviated, time: .shortened)
    }
}
