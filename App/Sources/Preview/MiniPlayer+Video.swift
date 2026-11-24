import JGDesign
import JGModel
import SwiftUI

/// The mini player's video: the picture with its scrubber and controls, or in Quick Preview over the whole window with
/// one bar over its bottom (WIN-062).
extension MiniPlayer {
    @ViewBuilder
    var video: some View {
        if let shown = overlayBarsShown {
            ZStack(alignment: .bottom) {
                surface
                QuickPreviewVideoBar(preview: preview, fullScreen: fullScreen)
                    .opacity(shown ? 1 : 0)
                    .allowsHitTesting(shown)
            }
        } else {
            regularVideo
        }
    }

    var surface: some View {
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

    var regularVideo: some View {
        VStack(spacing: JGSpacing.xs) {
            if preview.isFailed {
                failure
            } else {
                surface
            }
            PlaybackScrubber(playback: preview.playback, liveTime: preview.liveTime, isObserving: true)
                .frame(height: JGMetrics.controlHeightCompact)
            controls
        }
    }

    var videoAspect: CGFloat {
        if let size = preview.playback.info?.videoSize, size.height > 0 {
            return size.width / size.height
        }
        if let width = asset.width, let height = asset.height, height > 0 {
            return CGFloat(width) / CGFloat(height)
        }
        return 16 / 9
    }
}
