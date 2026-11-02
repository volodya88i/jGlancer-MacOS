import AppKit
import JGDesign
import JGModel
import JGThumbs
import SwiftUI

/// What the filmstrip shows for one file.
struct FilmstripItem: Equatable {
    let name: String
    let kind: MediaKind
    let thumbnail: ThumbnailRequest
}

/// A viewer whose folder the filmstrip shows: the photo pager or the player's queue.
@MainActor
protocol FilmstripSource: AnyObject {
    var filmstripCount: Int { get }
    var filmstripIndex: Int { get }
    var filmstripThumbnails: ThumbnailService { get }
    /// Nil while the item's row is still loading.
    func filmstripItem(at index: Int) -> FilmstripItem?
    /// Called for tiles coming on screen (loads rows lazily).
    func filmstripPrepare(around index: Int)
    func filmstripSelect(_ index: Int)
}

extension FilmstripSource {
    func filmstripPrepare(around _: Int) {}
}

/// The Picasa-3-style filmstrip of the viewers (docs/FEATURES.md §4.2–4.3): the other files of the folder on a
/// strip, the current one with the accent edge and kept in the middle; click to switch. Tiles are
/// created lazily as the strip scrolls and load their thumbnails only while on screen. With Reduce Transparency
/// the strip is opaque.
struct FilmstripView<Source: FilmstripSource>: View {
    let source: Source

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var reduceMotionOverride

    private var reduceMotion: Bool {
        systemReduceMotion || reduceMotionOverride
    }

    @State private var wheel = FilmstripWheel()

    var body: some View {
        let current = source.filmstripIndex
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(spacing: JGSpacing.xs) {
                        ForEach(0 ..< source.filmstripCount, id: \.self) { index in
                            FilmstripTile(source: source, index: index, isCurrent: index == current)
                                .id(index)
                        }
                    }
                    .padding(.horizontal, JGSpacing.m)
                    // A short strip stays centered, like Picasa's.
                    .frame(minWidth: geometry.size.width, maxHeight: .infinity)
                }
                .onAppear {
                    proxy.scrollTo(current, anchor: .center)
                    wheel.center = current
                    wheel.scroll = { index in
                        withAnimation(reduceMotion ? nil : .easeOut(duration: JGMetrics.fadeDuration)) {
                            proxy.scrollTo(index, anchor: .center)
                        }
                    }
                }
                .onHover { wheel.isHovered = $0 }
                .onDisappear { wheel.stop() }
                .onChange(of: current) {
                    wheel.center = current
                    withAnimation(reduceMotion ? nil : .easeOut(duration: JGMetrics.fadeDuration)) {
                        proxy.scrollTo(current, anchor: .center)
                    }
                }
            }
        }
        .frame(height: JGMetrics.filmstripHeight)
        .onChange(of: source.filmstripCount, initial: true) { wheel.count = source.filmstripCount }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(Text("Files in This Folder", comment: "Accessibility label of the viewer's filmstrip"))
    }
}

/// One file of the filmstrip: its thumbnail (or the kind glyph) and its name.
private struct FilmstripTile<Source: FilmstripSource>: View {
    let source: Source
    let index: Int
    let isCurrent: Bool

    @State private var image: CGImage?
    @State private var isHovered = false

    var body: some View {
        let item = source.filmstripItem(at: index)
        Button { source.filmstripSelect(index) } label: {
            VStack(spacing: JGSpacing.xxs) {
                ZStack {
                    JGShape(.small).fill(JGColor.bgRaised)
                    if let image {
                        Image(decorative: image, scale: 1)
                            .resizable()
                            .scaledToFit()
                    } else if let item {
                        Image(systemName: Self.glyph(item.kind))
                            .font(.system(size: JGMetrics.iconSize, weight: .light))
                            .foregroundStyle(JGColor.textTertiary)
                    }
                }
                .frame(width: JGMetrics.filmstripTileWidth, height: JGMetrics.filmstripTileHeight)
                .clipShape(JGShape(.small))
                .overlay {
                    if isCurrent {
                        JGShape(.small).strokeBorder(JGColor.accent, lineWidth: JGMetrics.selectionEdgeWidth)
                    } else if isHovered {
                        JGShape(.small).strokeBorder(JGColor.lineStrong, lineWidth: JGMetrics.outlineWidth)
                    }
                }
                Text(verbatim: item?.name ?? " ")
                    .jgTextStyle(.body)
                    .foregroundStyle(JGColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(width: JGMetrics.filmstripTileWidth)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
        .accessibilityLabel(Text(verbatim: item?.name ?? ""))
        .accessibilityAddTraits(isCurrent ? .isSelected : [])
        .onAppear { source.filmstripPrepare(around: index) }
        .task(id: item?.thumbnail) {
            guard let request = item?.thumbnail else {
                image = nil
                return
            }
            if let cached = source.filmstripThumbnails.cachedThumbnail(for: request) {
                image = cached
                return
            }
            image = await source.filmstripThumbnails.thumbnail(for: request, priority: .visible)
        }
    }

    static func glyph(_ kind: MediaKind) -> String {
        switch kind {
        case .photo: "photo"
        case .video: "film"
        case .audio: "waveform"
        }
    }
}

/// A small chevron centered above the filmstrip (down: hide it) or above what is left when it is hidden (up).
struct FilmstripToggle: View {
    @Binding var isCollapsed: Bool

    var body: some View {
        Button {
            isCollapsed.toggle()
        } label: {
            Image(systemName: isCollapsed ? "chevron.up" : "chevron.down")
                .font(.system(size: JGTextStyle.mono.size, weight: .semibold))
                .foregroundStyle(JGColor.textPrimary)
                .frame(width: JGMetrics.filmstripToggleWidth, height: JGMetrics.filmstripToggleHeight)
                .viewerGlass()
                .clipShape(JGShape(.small))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.bottom, JGSpacing.xxs)
        .help(isCollapsed ? Text("Show Filmstrip") : Text("Hide Filmstrip"))
        .accessibilityLabel(isCollapsed ? Text("Show Filmstrip") : Text("Hide Filmstrip"))
    }
}

/// A mouse wheel over the filmstrip (vertical notches, which a horizontal SwiftUI scroll view ignores) moves the
/// strip one file per notch; trackpads keep their native horizontal scrolling.
@MainActor
final class FilmstripWheel {
    var isHovered = false {
        didSet { isHovered ? start() : stop() }
    }

    var center = 0
    var count = 0
    var scroll: ((Int) -> Void)?
    private var monitor: Any?

    private func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, !event.hasPreciseScrollingDeltas else { return event }
            let delta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : -event.scrollingDeltaX
            guard delta != 0, count >= 1 else { return event }
            center = min(max(center + (delta > 0 ? -1 : 1), 0), count - 1)
            scroll?(center)
            return nil
        }
    }

    func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}
