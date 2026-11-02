import AVFoundation
import JGDesign
import JGPlayback
import SwiftUI

/// The audio viewer's media area (docs/FEATURES.md §4.3): cover art, then title, artist and album.
/// Without tags the file name is the title; without art a quiet tile with the audio glyph stands in.
struct AudioStage: View {
    let model: MediaViewerModel

    var body: some View {
        AudioStageContent(cover: model.cover, title: title, subtitle: subtitle)
    }

    private var title: String {
        let info = model.playback.info
        let name = model.current?.name ?? ""
        return info?.title ?? (name as NSString).deletingPathExtension
    }

    /// "Artist · Album", whichever is known.
    private var subtitle: String? {
        let info = model.playback.info
        let parts = [info?.artist, info?.album].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }
}

/// The next or previous song coming in from the edge during an animated swipe: its cover art, and its tags read up
/// front (until they arrive, the file name) — D-79.
struct SwipeNeighborAudio: View {
    let model: MediaViewerModel
    let index: Int
    @State private var cover: MediaViewerModel.Cover = .loading
    @State private var tags: MediaInfo?

    var body: some View {
        let items = model.playback.queue.items
        let name = items.indices.contains(index) ? items[index].name : ""
        let parts = [tags?.artist, tags?.album].compactMap(\.self)
        AudioStageContent(
            cover: cover, title: tags?.title ?? (name as NSString).deletingPathExtension,
            subtitle: parts.isEmpty ? nil : parts.joined(separator: " · ")
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .task(id: index) {
            guard items.indices.contains(index) else { return }
            let url = items[index].url
            async let info = try? MediaInfo.load(AVURLAsset(url: url))
            cover = await model.cover(at: index).map(MediaViewerModel.Cover.image) ?? .none
            tags = await info
        }
    }
}

/// Cover, title and subtitle, centered.
struct AudioStageContent: View {
    let cover: MediaViewerModel.Cover
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(spacing: JGSpacing.m) {
            coverView
            // A box of two title lines and one subtitle line, whatever the text: the cover never moves between
            // songs or while swiping (D-79).
            ZStack(alignment: .top) {
                lines(title: "\n", subtitle: " ").hidden()
                lines(title: title, subtitle: subtitle)
            }
            .frame(maxWidth: JGMetrics.readableTextWidth)
        }
        .accessibilityElement(children: .combine)
    }

    private func lines(title: String, subtitle: String?) -> some View {
        VStack(spacing: JGSpacing.xxs) {
            Text(verbatim: title)
                .jgTextStyle(.heading)
                .foregroundStyle(JGColor.textPrimary)
                .lineLimit(2)
                .multilineTextAlignment(.center)
            if let subtitle {
                Text(verbatim: subtitle)
                    .jgTextStyle(.body)
                    .foregroundStyle(JGColor.textSecondary)
                    .lineLimit(1)
            }
        }
    }

    @ViewBuilder
    private var coverView: some View {
        let side = JGMetrics.coverArtSide
        switch cover {
        case let .image(image):
            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: side, maxHeight: side)
                .clipShape(JGShape(.medium))
        case .none, .loading:
            JGShape(.medium)
                .fill(JGColor.bgRaised)
                .frame(width: side, height: side)
                .overlay {
                    if cover == .none {
                        Image(systemName: "waveform")
                            .font(.system(size: JGMetrics.tileGlyphSize * 2, weight: .light))
                            .foregroundStyle(JGColor.textTertiary)
                    }
                }
                .accessibilityHidden(true)
        }
    }
}
