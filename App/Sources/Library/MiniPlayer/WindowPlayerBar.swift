import JGDesign
import JGPlayback
import SwiftUI

/// The bar of the window's mini player (D-88): cover, title and artist, the source folder (a click shows the song),
/// previous / play / next, time, scrubber (silent while dragged), speed, mute, volume, loop, play next and × to close, on the blurred
/// cover when Settings → Effects has it.
struct WindowPlayerBar: View {
    let player: WindowPlayerModel
    let onShowSong: (Int64) -> Void

    private var playback: PlaybackController {
        player.playback
    }

    var body: some View {
        HStack(spacing: JGSpacing.s) {
            cover
            VStack(alignment: .leading, spacing: 0) {
                Text(verbatim: title)
                    .jgTextStyle(.body)
                    .foregroundStyle(JGColor.textPrimary)
                    .lineLimit(1)
                if let subtitle {
                    Text(verbatim: subtitle)
                        .jgTextStyle(.body)
                        .foregroundStyle(JGColor.textSecondary)
                        .lineLimit(1)
                }
                if let folder = player.folderName, let id = player.current?.assetID {
                    Button { onShowSong(id) } label: {
                        Text(verbatim: folder)
                            .jgTextStyle(.mono)
                            .foregroundStyle(JGColor.textTertiary)
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                    .help(Text("Show the song in the library", comment: "Mini player: the folder link"))
                }
            }
            .frame(minWidth: JGMetrics.miniPlayerTextMinWidth, maxWidth: JGMetrics.miniPlayerTextWidth, alignment: .leading)
            controls
            PlaybackScrubber(playback: playback, liveTime: player.liveTime, isObserving: player.isOpen)
                .frame(minWidth: JGMetrics.miniPlayerScrubberMinWidth)
                .frame(height: JGMetrics.controlHeightCompact)
                .layoutPriority(1)
            PlaybackTimeLabel(playback: playback)
                .fixedSize()
            SpeedMenu(tuning: player.tuning, kind: .audio)
            VolumeControl(tuning: player.tuning)
            // As in the big player (D-120).
            ViewerIconButton(symbol: "repeat", label: Text("Loop", comment: "Player: repeat the current file"), isOn: playback.loops) {
                playback.loops.toggle()
            }
            ViewerIconButton(
                symbol: "text.line.last.and.arrowtriangle.forward",
                label: Text("Play Next", comment: "Player: continue with the next file at the end"),
                isOn: playback.autoAdvance
            ) {
                player.tuning.setPlaysNext(!playback.autoAdvance, for: .audio)
            }
            ViewerIconButton(symbol: "xmark", label: Text("Close", comment: "Mini player: closes the bar"), action: player.close)
        }
        .padding(.horizontal, JGSpacing.m)
        .frame(height: JGMetrics.miniPlayerHeight)
        .background {
            // The blurred cover, as behind the big player (Settings → Effects; W-99).
            ZStack {
                Rectangle().fill(JGColor.bgPopup)
                CoverBackdropView(cover: player.cover)
            }
        }
    }

    private var title: String {
        playback.info?.title ?? ((player.current?.name ?? "") as NSString).deletingPathExtension
    }

    private var subtitle: String? {
        let parts = [playback.info?.artist, playback.info?.album].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    @ViewBuilder
    private var cover: some View {
        let side = JGMetrics.miniPlayerHeight - JGSpacing.s * 2
        if let cover = player.cover {
            Image(decorative: cover, scale: 1)
                .resizable()
                .scaledToFill()
                .frame(width: side, height: side)
                .clipShape(JGShape(.small))
        } else {
            JGShape(.small)
                .fill(JGColor.bgRaised)
                .frame(width: side, height: side)
                .overlay {
                    Image(systemName: "waveform").foregroundStyle(JGColor.textTertiary)
                }
                .accessibilityHidden(true)
        }
    }

    private var controls: some View {
        HStack(spacing: 0) {
            ViewerIconButton(
                symbol: "backward.end.fill",
                label: Text("Previous", comment: "Player: previous file"),
                action: player.previous
            )
            ViewerIconButton(
                symbol: playback.isPlaying ? "pause.fill" : "play.fill",
                label: playback.isPlaying ? Text("Pause", comment: "Player") : Text("Play", comment: "Player"),
                action: player.togglePlay
            )
            ViewerIconButton(symbol: "forward.end.fill", label: Text("Next", comment: "Player: next file"), action: player.next)
                .disabled(!playback.queue.hasNext)
        }
    }
}
