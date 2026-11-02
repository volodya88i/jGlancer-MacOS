import JGDesign
import JGSettings
import SwiftUI

/// The viewers' filmstrip with its way of coming and going (Settings → Appearance → Filmstrip): with the button,
/// a chevron hides and shows it (remembered); automatic, it slides in while the pointer is near the bottom of the
/// viewer and leaves shortly after the pointer moves up. Nothing for a folder of one file.
struct FilmstripPanel<Source: FilmstripSource>: View {
    let source: Source
    /// The viewer's pointer tracking; needed for the automatic mode.
    let reveal: FilmstripRevealer

    @Environment(\.appSettings) private var settings
    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var reduceMotionOverride
    @AppStorage("FilmstripCollapsed") private var isCollapsed = false

    var body: some View {
        if source.filmstripCount > 1 {
            if settings.filmstripReveal == .automatic {
                automatic
            } else {
                VStack(spacing: 0) {
                    FilmstripToggle(isCollapsed: $isCollapsed)
                    if !isCollapsed {
                        strip
                    }
                }
            }
        }
    }

    private var strip: some View {
        FilmstripView(source: source)
            .viewerGlass(tint: JGMetrics.filmstripScrimOpacity)
            .overlay(alignment: .top) { JGHairline() }
    }

    /// Takes no room: the strip floats over what is above it, so nothing moves when it comes and goes.
    private var automatic: some View {
        Color.clear
            .frame(height: 0)
            .frame(maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.frame(in: .named(FilmstripRevealer.space)).maxY } action: { reveal.bottom = $0 }
            .overlay(alignment: .bottom) {
                if reveal.isShown {
                    strip.transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(systemReduceMotion || reduceMotionOverride ? nil : .easeOut(duration: JGMetrics.fadeDuration), value: reveal.isShown)
    }
}

/// Pointer tracking for the automatic filmstrip: shown while the pointer is in the band from the strip's top edge
/// down to the bottom of the viewer, hidden `JGMetrics.filmstripHideDelay` after it leaves. One cancellable task, no
/// timer. Viewers name their root `FilmstripRevealer.space` and pass pointer moves.
@MainActor
@Observable
final class FilmstripRevealer {
    nonisolated static let space = "viewer"

    private(set) var isShown = false
    /// Where the strip's bottom edge sits in the viewer (the top of the controls below it, or the viewer's bottom).
    @ObservationIgnored var bottom: CGFloat = .infinity
    @ObservationIgnored private var hideTask: Task<Void, Never>?

    /// The pointer at `point` in the viewer, or nil when it left the viewer.
    func pointer(at point: CGPoint?) {
        guard let point else {
            scheduleHide()
            return
        }
        if point.y >= bottom - JGMetrics.filmstripHeight - JGMetrics.filmstripRevealMargin {
            show()
        } else {
            scheduleHide()
        }
    }

    private func show() {
        hideTask?.cancel()
        hideTask = nil
        if !isShown {
            isShown = true
        }
    }

    private func scheduleHide() {
        guard isShown, hideTask == nil else { return }
        hideTask = Task {
            try? await Task.sleep(for: .seconds(JGMetrics.filmstripHideDelay))
            guard !Task.isCancelled else { return }
            isShown = false
            hideTask = nil
        }
    }

    func stop() {
        hideTask?.cancel()
        hideTask = nil
    }
}
