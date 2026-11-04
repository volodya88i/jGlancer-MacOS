import AppKit
import JGDesign
import JGPlayback
import JGSettings
import SwiftUI

/// The video and audio viewers filling the window (docs/FEATURES.md §4.2–4.3, docs/DESIGN.md §8).
///
/// Video: the picture on `bg.media`, the top bar, the filmstrip and the scrubber with the controls row; they
/// hide while the video plays and the pointer rests, and stay while paused. Audio: cover art and tags, the
/// filmstrip, a large waveform scrubber and the controls, always visible; only the light top bar hides when the pointer
/// rests, playing or paused (WIN-027). The filmstrip can be collapsed.
struct MediaViewerView: View {
    let model: MediaViewerModel
    /// "‹ Library".
    let onClose: () -> Void
    /// Esc (outside full screen); the same as `onClose` unless the viewer was opened on its own.
    var onEscape: (() -> Void)?
    let onAddFolder: (URL) -> Void
    var contextMenu: () -> NSMenu? = { nil }

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var reduceMotionOverride

    private var reduceMotion: Bool {
        systemReduceMotion || reduceMotionOverride
    }

    @State private var hider = IdleHider()
    @State private var isPointerOnControls = false
    /// The audio player's top bar: shown, and whether the pointer keeps it so.
    @State private var isAudioBarVisible = true
    @State private var isPointerOnAudioBar = false
    @State private var isFullScreen = false
    @State private var filmstripReveal = FilmstripRevealer()
    @State private var pager = SwipePager()
    /// The cover behind the song: kept while the next one loads, so the backdrop never flashes empty.
    @State private var backdropCover: CGImage?
    @State private var neighborCover: CGImage?
    @Environment(\.appSettings) private var settings

    private var playback: PlaybackController {
        model.playback
    }

    var body: some View {
        ZStack {
            Rectangle().fill(JGColor.bgMedia)
            if model.kind == .audio {
                // The swiped-in song's cover blends in with the swipe (D-79).
                CoverBackdropView(
                    cover: backdropCover, incoming: pager.neighbor == 0 ? nil : neighborCover,
                    blend: pager.width > 0 ? Double(abs(pager.offset) / pager.width) : 0
                )
            }
            MediaSurface(
                player: model.kind == .video ? playback.player : nil,
                sampleLayer: model.kind == .video ? playback.matroskaLayer : nil,
                accessibilityLabel: model.current?.name ?? "",
                onCommand: perform, onActivity: showChrome, contextMenu: contextMenu,
                // Songs swipe with an animation; a video at fit pages at once (D-80).
                onSwipe: { pager.handle($0) },
                allowsZoom: model.kind == .video, zoomResetID: model.current?.url
            )
            if model.kind == .audio {
                audioLayout
            } else {
                if model.isFailed {
                    failure
                }
                videoChrome
            }
        }
        .ignoresSafeArea()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pager.width = $0 }
        .onChange(of: settings.swipeAnimation && !reduceMotion, initial: true) { _, isAnimated in
            pager.isAnimated = isAnimated && model.kind == .audio
            pager.canPage = { [playback] in playback.queue.items.indices.contains(playback.queue.index + $0) }
            pager.page = { [playback] direction in
                // The swiped-in cover is on screen already: it becomes the backdrop at once.
                if let neighborCover {
                    backdropCover = neighborCover
                }
                playback.select(playback.queue.index + direction)
            }
        }
        .coordinateSpace(.named(FilmstripRevealer.space))
        .onContinuousHover(coordinateSpace: .named(FilmstripRevealer.space)) { phase in
            if case let .active(point) = phase {
                filmstripReveal.pointer(at: point)
                showChrome()
            } else {
                filmstripReveal.pointer(at: nil)
            }
        }
        .onAppear(perform: showChrome)
        .onDisappear {
            hider.cancel()
            filmstripReveal.stop()
        }
        .onAppear { isFullScreen = NSApp.keyWindow?.styleMask.contains(.fullScreen) ?? false }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { _ in
            isFullScreen = true
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { _ in
            isFullScreen = false
        }
        .onChange(of: playback.isPlaying) { showChrome() }
        .onChange(of: playback.queue.index) { showChrome() }
        // Another file: the segment belonged to the last one.
        .onChange(of: model.current) { model.endSegmentMode() }
        .onChange(of: model.cover, initial: true) { _, cover in
            switch cover {
            case let .image(image): backdropCover = image
            case .none: backdropCover = nil
            case .loading: break
            }
        }
        .task(id: model.kind == .audio && pager.neighbor != 0 ? playback.queue.index + pager.neighbor : nil) {
            let index = playback.queue.index + pager.neighbor
            neighborCover = pager.neighbor == 0 ? nil : await model.cover(at: index)
        }
        .task(id: model.current) {
            if let item = model.current {
                await model.loadCover(for: item)
            }
        }
        .task(id: WaveformKey(item: model.current, videoWaveform: settings.videoWaveformStyle == .narrow)) {
            if let item = model.current {
                await model.loadWaveform(for: item, video: settings.videoWaveformStyle == .narrow)
            }
        }
        .task(id: model.current) {
            if let item = model.current {
                await model.loadAnalysis(for: item)
            }
        }
    }

    // MARK: Video

    private var videoChrome: some View {
        VStack(spacing: 0) {
            topBar
            Spacer()
            VStack(spacing: 0) {
                FilmstripPanel(source: model, reveal: filmstripReveal)
                // The controls row sits centred between the scrubber and the bottom edge (D-78).
                VStack(spacing: JGSpacing.xs) {
                    // The sound's waveform when Decor → Video player says so (D-110).
                    PlaybackScrubber(
                        playback: playback, liveTime: model.liveTime,
                        waveform: settings.videoWaveformStyle == .narrow ? model.waveform ?? Self.silence : nil,
                        style: settings.videoWaveformStyle, isObserving: model.isChromeVisible, segmentModel: model
                    )
                    .frame(
                        height: settings.videoWaveformStyle == .narrow ? JGMetrics.videoWaveformHeight : JGMetrics.controlHeightCompact
                    )
                    PlaybackControls(model: model, isFullScreen: isFullScreen, onToggleFullScreen: toggleFullScreen)
                }
                .padding(.horizontal, JGSpacing.m)
                .padding(.top, JGSpacing.xxs)
                .padding(.bottom, JGSpacing.xs)
                .viewerGlass()
                .overlay(alignment: .top) { JGHairline() }
            }
            .onHover { isPointerOnControls = $0 }
        }
        .opacity(model.isChromeVisible ? 1 : 0)
        .animation(reduceMotion ? nil : .easeOut(duration: JGMetrics.fadeDuration), value: model.isChromeVisible)
    }

    // MARK: Audio

    private var audioLayout: some View {
        VStack(spacing: 0) {
            // Its place stays when it hides: nothing shifts.
            topBar
                .opacity(isAudioBarVisible ? 1 : 0)
                .allowsHitTesting(isAudioBarVisible)
                .animation(reduceMotion ? nil : .easeOut(duration: JGMetrics.fadeDuration), value: isAudioBarVisible)
                .onHover { isPointerOnAudioBar = $0 }
            Spacer(minLength: JGSpacing.l)
            if model.isFailed {
                failure
            } else {
                AudioStage(model: model)
                    // Clicks and drags go through to the surface underneath (swipes, double-click).
                    .allowsHitTesting(false)
                    .overlay {
                        if pager.neighbor != 0 {
                            SwipeNeighborAudio(model: model, index: playback.queue.index + pager.neighbor)
                                .offset(x: CGFloat(pager.neighbor) * pager.width)
                        }
                    }
                    .offset(x: pager.offset)
            }
            Spacer(minLength: JGSpacing.l)
            FilmstripPanel(source: model, reveal: filmstripReveal)
            VStack(spacing: JGSpacing.m) {
                // A hairline until the first peaks arrive, then the waveform fills in.
                PlaybackScrubber(
                    playback: playback, liveTime: model.liveTime, waveform: model.waveform ?? Self.silence, isObserving: true,
                    segmentModel: model
                )
                .frame(height: settings.waveformStyle == .timeline ? JGMetrics.controlHeightCompact : JGMetrics.waveformHeight)
                PlaybackControls(model: model, isFullScreen: isFullScreen, onToggleFullScreen: toggleFullScreen)
            }
            .padding(.top, JGSpacing.s)
            .frame(maxWidth: JGMetrics.playerMaxWidth)
            .padding(.horizontal, JGSpacing.l)
            .padding(.bottom, JGSpacing.m)
        }
    }

    private static let silence = JGWaveformPeaks(lows: [0], highs: [0])

    // MARK: Shared

    private var topBar: some View {
        ViewerTopBar(
            name: model.current?.name ?? "", index: playback.queue.index, count: playback.queue.count,
            assetID: model.current?.assetID, onClose: onClose, onEscape: escape, isLight: model.kind == .audio
        ) {
            if let folder = model.folderToOffer {
                AddFolderButton {
                    onAddFolder(folder)
                    model.dismissFolderOffer()
                }
            }
        }
    }

    private var failure: some View {
        ViewerMessage(
            symbol: model.kind == .video ? "film" : "waveform",
            text: Text("Can't play this file.", comment: "Player state for an unsupported or damaged file")
        ) {
            if let url = model.current?.url {
                HStack(spacing: JGSpacing.xs) {
                    OpenWithMenu(url: url)
                    RevealInFinderButton(url: url)
                }
                .padding(.top, JGSpacing.xs)
            }
        }
    }

    private func perform(_ command: MediaCommand) {
        if command == .toggleFullScreen {
            toggleFullScreen()
        } else {
            model.perform(command)
        }
    }

    private func toggleFullScreen() {
        NSApp.keyWindow?.toggleFullScreen(nil)
    }

    /// Esc leaves full screen first, then the viewer.
    private func escape() {
        if let window = NSApp.keyWindow, window.styleMask.contains(.fullScreen) {
            window.toggleFullScreen(nil)
        } else {
            (onEscape ?? onClose)()
        }
    }
}

// MARK: Chrome

extension MediaViewerView {
    /// Shows the chrome; while video plays it hides again after a short idle unless the pointer is on the controls.
    func showChrome() {
        if !model.isChromeVisible {
            model.isChromeVisible = true
        }
        if model.kind == .audio {
            isAudioBarVisible = true
            hider.schedule(hidesCursor: false) {
                if !isPointerOnAudioBar {
                    isAudioBarVisible = false
                }
                return false
            }
            return
        }
        guard model.kind == .video, playback.isPlaying else {
            hider.cancel()
            return
        }
        hider.schedule {
            guard !isPointerOnControls, playback.isPlaying else { return false }
            model.isChromeVisible = false
            return true
        }
    }
}

/// The waveform loads again for another file, or when the video player starts or stops showing one.
private struct WaveformKey: Equatable {
    let item: PlaybackItem?
    let videoWaveform: Bool
}
