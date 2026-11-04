import JGDesign
import JGSettings
import JGThumbs
import SwiftUI

/// The cover art of an audio file as heavy frosted glass behind it (Settings → Appearance → Blurred cover behind
/// audio): a tiny blurred copy (`CoverBackdrop`) stretched to fill, under a strong wash of the theme's base color
/// (dark in the dark theme, near white in the light one) so text stays readable.
/// While a song is swiped, the next cover (`incoming`) blends in by `blend` (0…1, driven by the swipe); when it
/// becomes the cover it is already on screen, so nothing fades again. Any other new cover cross-fades in over
/// `JGMetrics.backdropCrossfade` (D-79, W-82). Nothing is shown without the setting, without art, or with Reduce
/// Transparency.
struct CoverBackdropView: View {
    let cover: CGImage?
    var incoming: CGImage?
    var blend: Double = 0

    @Environment(\.appSettings) private var settings
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var reduceMotionOverride
    /// Blurred copies of the covers seen lately, by image.
    @State private var rendered: [ObjectIdentifier: CGImage] = [:]
    /// The last cover blended in by a swipe.
    @State private var lastIncoming: ObjectIdentifier?
    /// The blurred copy on screen: it stays while the next cover's copy is still being made, so paging never blanks
    /// the backdrop for a moment (D-119).
    @State private var shown: CGImage?

    /// Rendered copies kept (the current cover, its neighbors, the one before).
    private static let kept = 4

    private var isOn: Bool {
        settings.coverBackdrop && !reduceTransparency
    }

    var body: some View {
        let coverID = cover.map(ObjectIdentifier.init)
        // A song without art lets the backdrop go; one whose copy is not made yet keeps the last one.
        let current = cover == nil ? nil : coverID.flatMap { rendered[$0] } ?? shown
        let next = incoming.map(ObjectIdentifier.init).flatMap { rendered[$0] }
        let fades = !(systemReduceMotion || reduceMotionOverride) && coverID != lastIncoming
        // The container sets the size; the filled image never makes it larger.
        Color.clear
            .overlay {
                if isOn, let current {
                    layer(current).id(ObjectIdentifier(current)).transition(.opacity)
                }
            }
            .overlay {
                if isOn, let next, blend > 0 {
                    layer(next).opacity(min(blend, 1))
                }
            }
            .overlay {
                if isOn, current != nil || next != nil {
                    Rectangle().fill(JGColor.bgBase).opacity(JGMetrics.backdropScrimOpacity)
                }
            }
            .clipped()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .animation(fades ? .easeInOut(duration: JGMetrics.backdropCrossfade) : nil, value: current.map(ObjectIdentifier.init))
            .task(id: isOn ? coverID : nil) { await render(cover) }
            .task(id: isOn ? incoming.map(ObjectIdentifier.init) : nil) { await render(incoming) }
            .onChange(of: current.map(ObjectIdentifier.init), initial: true) { shown = current }
            .onChange(of: incoming.map(ObjectIdentifier.init)) { _, id in
                if let id {
                    lastIncoming = id
                }
            }
    }

    private func render(_ image: CGImage?) async {
        guard isOn, let image, rendered[ObjectIdentifier(image)] == nil else { return }
        let blurred = await CoverBackdrop.render(image)
        guard !Task.isCancelled, let blurred else { return }
        if rendered.count >= Self.kept {
            let keep = Set([cover, incoming].compactMap { $0.map(ObjectIdentifier.init) })
            rendered = rendered.filter { keep.contains($0.key) }
        }
        rendered[ObjectIdentifier(image)] = blurred
    }

    private func layer(_ image: CGImage) -> some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .scaledToFill()
    }
}
