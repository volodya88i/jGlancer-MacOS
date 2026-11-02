import JGDesign
import JGSettings
import SwiftUI

/// The photo viewer filling the window (docs/DESIGN.md §8): the image on `bg.media`, a HUD that fades after a
/// short idle (keyboard keeps working) with the top bar, ‹ › arrows at the sides and the filmstrip, and an offer
/// to add the folder of a file opened from outside.
struct PhotoViewerView: View {
    let model: PhotoViewerModel
    /// "‹ Library".
    let onClose: () -> Void
    /// Esc; the same as `onClose` unless the viewer was opened on its own.
    var onEscape: (() -> Void)?
    let onAddFolder: (URL) -> Void
    var contextMenu: () -> NSMenu? = { nil }

    @Environment(\.accessibilityReduceMotion) private var systemReduceMotion
    @Environment(\.reduceMotionOverride) private var reduceMotionOverride

    private var reduceMotion: Bool {
        systemReduceMotion || reduceMotionOverride
    }

    @State private var zoomCommand: (command: ZoomCommand, serial: Int)?
    @State private var hider = IdleHider()
    @State private var filmstripReveal = FilmstripRevealer()
    @State private var pager = SwipePager()
    @Environment(\.appSettings) private var settings

    var body: some View {
        ZStack {
            Rectangle().fill(JGColor.bgMedia)
            PhotoCanvas(
                model: model, picture: model.shownPicture, index: model.index, zoomCommand: zoomCommand, pager: pager,
                onClose: onEscape ?? onClose, onActivity: showHUD, contextMenu: contextMenu
            )
            .offset(x: pager.offset)
            if pager.neighbor != 0 {
                SwipeNeighborPhoto(picture: model.neighborPicture(by: pager.neighbor))
                    .offset(x: pager.offset + CGFloat(pager.neighbor) * pager.width)
            }
            if model.failed {
                ViewerMessage(
                    symbol: "photo",
                    text: Text("Can't open this photo.", comment: "Viewer state for a corrupt or unsupported image")
                ) {}
            }
            VStack(spacing: 0) {
                ViewerTopBar(
                    name: model.currentPhoto?.name ?? "", index: model.index, count: model.count,
                    assetID: model.currentPhoto?.assetID, onClose: onClose, onEscape: onEscape
                ) {
                    if let folder = model.folderToOffer {
                        AddFolderButton {
                            onAddFolder(folder)
                            model.dismissFolderOffer()
                        }
                    }
                    ViewerIconButton(symbol: "rotate.left", label: Text("Rotate Left", comment: "Action")) {
                        model.rotate(by: -1)
                    }
                    ViewerIconButton(symbol: "rotate.right", label: Text("Rotate Right", comment: "Action")) {
                        model.rotate(by: 1)
                    }
                    zoomButton(.fit, symbol: "arrow.down.right.and.arrow.up.left", label: Text("Fit", comment: "Zoom to fit the window"))
                    zoomButton(.actualSize, symbol: "1.magnifyingglass", label: Text("Actual Size", comment: "Zoom to 100 %"))
                }
                ZStack {
                    HStack {
                        pageButton(by: -1, symbol: "chevron.left", label: Text("Previous", comment: "Player: previous file"))
                        Spacer()
                        pageButton(by: 1, symbol: "chevron.right", label: Text("Next", comment: "Player: next file"))
                    }
                    .padding(.horizontal, JGSpacing.m)
                }
                .frame(maxHeight: .infinity)
                FilmstripPanel(source: model, reveal: filmstripReveal)
            }
            .opacity(model.isHUDVisible ? 1 : 0)
            .animation(reduceMotion ? nil : .easeOut(duration: JGMetrics.fadeDuration), value: model.isHUDVisible)
        }
        .ignoresSafeArea()
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { pager.width = $0 }
        .onChange(of: settings.swipeAnimation && !reduceMotion, initial: true) { _, isAnimated in
            pager.isAnimated = isAnimated
            pager.canPage = { [model] in model.canMove(by: $0) }
            pager.page = { [model] in model.move(by: $0) }
        }
        .coordinateSpace(.named(FilmstripRevealer.space))
        .background { arrowKeys }
        .onContinuousHover(coordinateSpace: .named(FilmstripRevealer.space)) { phase in
            if case let .active(point) = phase {
                filmstripReveal.pointer(at: point)
                showHUD()
            } else {
                filmstripReveal.pointer(at: nil)
            }
        }
        .onAppear(perform: showHUD)
        .onDisappear {
            hider.cancel()
            filmstripReveal.stop()
        }
    }

    /// ← and → page through the folder wherever the keyboard focus is (filmstrip, HUD buttons, the photo).
    private var arrowKeys: some View {
        ZStack {
            Button("") { page(by: -1) }
                .keyboardShortcut(.leftArrow, modifiers: [])
            Button("") { page(by: 1) }
                .keyboardShortcut(.rightArrow, modifiers: [])
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
    }

    private func page(by offset: Int) {
        model.move(by: offset)
        showHUD()
    }

    /// A round ‹ or › at the side of the photo; hidden at the ends of the folder.
    @ViewBuilder
    private func pageButton(by offset: Int, symbol: String, label: Text) -> some View {
        let target = model.index + offset
        if target >= 0, target < model.count {
            Button {
                page(by: offset)
            } label: {
                Image(systemName: symbol)
                    .font(.system(size: JGTextStyle.heading.size, weight: .medium))
                    .foregroundStyle(JGColor.textPrimary)
                    .frame(width: JGMetrics.pageButtonSide, height: JGMetrics.pageButtonSide)
                    .background(.ultraThinMaterial, in: Circle())
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(label)
            .accessibilityLabel(label)
        }
    }

    private func zoomButton(_ command: ZoomCommand, symbol: String, label: Text) -> some View {
        ViewerIconButton(symbol: symbol, label: label) {
            zoomCommand = (command, (zoomCommand?.serial ?? 0) + 1)
        }
    }

    /// Shows the HUD and schedules one cancellable fade.
    private func showHUD() {
        if !model.isHUDVisible {
            model.isHUDVisible = true
        }
        hider.schedule {
            // The automatic filmstrip stays while the pointer is on it.
            guard !filmstripReveal.isShown else { return false }
            model.isHUDVisible = false
            return true
        }
    }
}

/// The photo coming in from the edge during an animated swipe, sized as the canvas shows it at fit (never enlarged
/// past 100 %); the background shows until its screen-size decode is ready.
private struct SwipeNeighborPhoto: View {
    let picture: PhotoViewerModel.Picture?
    @Environment(\.displayScale) private var displayScale

    var body: some View {
        GeometryReader { geometry in
            if let picture {
                let size = fittedSize(picture.fullSize, in: geometry.size)
                Image(decorative: picture.image, scale: 1)
                    .resizable()
                    .frame(width: size.width, height: size.height)
                    .position(x: geometry.size.width / 2, y: geometry.size.height / 2)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    /// The photo's points at 100 % (one pixel per device pixel), scaled down to fit.
    private func fittedSize(_ pixels: CGSize, in viewport: CGSize) -> CGSize {
        let points = CGSize(width: pixels.width / displayScale, height: pixels.height / displayScale)
        guard points.width > 0, points.height > 0 else { return .zero }
        let scale = min(1, viewport.width / points.width, viewport.height / points.height)
        return CGSize(width: points.width * scale, height: points.height * scale)
    }
}
