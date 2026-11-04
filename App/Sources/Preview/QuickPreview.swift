import AppKit
import Carbon.HIToolbox
import JGDesign
import SwiftUI

/// Quick Preview (docs/FEATURES.md §3, ARCHITECTURE §17): a floating panel that never takes the keyboard from the
/// library, so arrows keep moving the selection and the preview follows. Space or Esc closes it (handled by the
/// grid), Return or a click on the media toggles pause. A photo or video can go full screen like in the viewer (the
/// button or F); there Esc and Space leave full screen first. Its size and position are remembered. It floats above
/// every window, also while another app is active (W-90), and Open in Viewer hands its file to the viewer (W-89).
@MainActor
final class QuickPreviewController: NSObject, NSWindowDelegate {
    private let preview: PreviewModel
    private let settings: SettingsStore
    private let flagBook: FlagBook?
    /// Called when Quick Preview over Finder closes (the app quits if the service launched it).
    var onExternalEnd: (() -> Void)?
    /// Get Info of the file shown (D-78).
    var onInfo: (() -> Void)?
    /// Open in Viewer: the file shown goes to the full viewer (W-89).
    var onOpenInViewer: (() -> Void)?
    private var panel: QuickPreviewPanel?
    /// Close once full screen has been left.
    private var closesAfterFullScreen = false

    init(preview: PreviewModel, settings: SettingsStore, flagBook: FlagBook? = nil) {
        self.preview = preview
        self.settings = settings
        self.flagBook = flagBook
    }

    var isOpen: Bool {
        panel?.isVisible == true
    }

    func toggle(over window: NSWindow?) {
        if isOpen {
            close()
        } else {
            open(over: window)
        }
    }

    func open(over window: NSWindow?) {
        guard preview.asset != nil else {
            NSSound.beep()
            return
        }
        let panel = panel ?? makePanel(over: window)
        self.panel = panel
        panel.orderFront(nil)
        preview.setQuickPreviewOpen(true)
    }

    var isFullScreen: Bool {
        panel?.styleMask.contains(.fullScreen) == true
    }

    /// Showing files from Finder (Services ▸ Quick Preview).
    var isExternal: Bool {
        panel?.isExternal == true
    }

    func toggleFullScreen() {
        panel?.toggleFullScreen(nil)
    }

    func close() {
        guard isOpen else { return }
        if isFullScreen {
            closesAfterFullScreen = true
            toggleFullScreen()
            return
        }
        panel?.orderOut(nil)
        preview.setQuickPreviewOpen(false)
        endExternal()
    }

    func windowWillClose(_: Notification) {
        preview.setQuickPreviewOpen(false)
        endExternal()
    }

    // MARK: Files from Finder

    /// Quick Preview over Finder (Services ▸ Quick Preview) without bringing the app forward: the panel takes the
    /// keyboard itself (Space or Esc close, arrows go through the files, Return pauses) and stays when another app
    /// is active. F toggles full screen.
    func openExternal() {
        let panel = panel ?? makePanel(over: nil)
        self.panel = panel
        panel.isExternal = true
        panel.onKey = { [weak self] event in self?.handleExternalKey(event) ?? false }
        panel.orderFrontRegardless()
        panel.makeKey()
        preview.setQuickPreviewOpen(true)
    }

    private func handleExternalKey(_ event: NSEvent) -> Bool {
        guard event.modifierFlags.isDisjoint(with: [.command, .control, .option]) else { return false }
        switch event.specialKey {
        case .leftArrow?, .upArrow?: preview.moveExternal(by: -1)
        case .rightArrow?, .downArrow?: preview.moveExternal(by: 1)
        case .carriageReturn?, .enter?: preview.togglePlayPause()
        case _ where event.keyCode == UInt16(kVK_ANSI_F): toggleFullScreen()
        default:
            // Esc (53) and Space (49): full screen is left first, then the panel closes.
            guard event.keyCode == 53 || event.keyCode == 49 else { return false }
            if isFullScreen {
                toggleFullScreen()
            } else {
                close()
            }
        }
        return true
    }

    private func endExternal() {
        guard let panel, panel.isExternal else { return }
        panel.isExternal = false
        panel.onKey = nil
        preview.endExternal()
        let end = onExternalEnd
        onExternalEnd = nil
        end?()
    }

    func windowDidExitFullScreen(_: Notification) {
        if closesAfterFullScreen {
            closesAfterFullScreen = false
            close()
        }
    }

    private func makePanel(over window: NSWindow?) -> QuickPreviewPanel {
        let panel = QuickPreviewPanel()
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: QuickPreviewView(
            preview: preview, onToggleFullScreen: { [weak self] in self?.toggleFullScreen() },
            onInfo: { [weak self] in self?.onInfo?() },
            onOpenInViewer: { [weak self] in self?.onOpenInViewer?() }
        ).appSettings(settings).environment(\.flagBook, flagBook))
        if !panel.setFrameUsingName(QuickPreviewPanel.frameName) {
            let size = CGSize(width: JGMetrics.quickPreviewWidth, height: JGMetrics.quickPreviewHeight)
            let center = window.map { CGPoint(x: $0.frame.midX, y: $0.frame.midY) } ?? .zero
            panel.setFrame(
                CGRect(x: center.x - size.width / 2, y: center.y - size.height / 2, width: size.width, height: size.height),
                display: false
            )
        }
        // The window is never narrower than its controls row (the content's own minimum, set by the hosting view, and
        // `minSize`), also when a narrower frame was saved before (D-112).
        let least = max(panel.minSize.width, panel.contentView?.fittingSize.width ?? 0)
        if panel.frame.width < least {
            var frame = panel.frame
            frame.size.width = least
            panel.setFrame(frame, display: false)
        }
        panel.setFrameAutosaveName(QuickPreviewPanel.frameName)
        return panel
    }
}

/// A non-activating floating panel: clicks reach its controls, the keyboard stays with the library. It stays above
/// every window while another app is active (W-90). For files from Finder (`isExternal`) it takes the keyboard itself.
final class QuickPreviewPanel: NSPanel {
    static let frameName = "QuickPreview"

    var isExternal = false

    /// Keys while external; true when handled.
    var onKey: ((NSEvent) -> Bool)?

    init() {
        super.init(
            contentRect: CGRect(x: 0, y: 0, width: JGMetrics.quickPreviewWidth, height: JGMetrics.quickPreviewHeight),
            styleMask: [.titled, .closable, .resizable, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered, defer: true
        )
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isFloatingPanel = true
        level = .floating
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        isMovableByWindowBackground = true
        collectionBehavior.insert(.fullScreenPrimary)
        minSize = CGSize(width: JGMetrics.previewPaneMinWidth, height: JGMetrics.previewPaneMinWidth)
        standardWindowButton(.miniaturizeButton)?.isHidden = true
        standardWindowButton(.zoomButton)?.isHidden = true
        setAccessibilityLabel(String(localized: "Quick Preview", comment: "Accessibility label of the Quick Preview window"))
    }

    override var canBecomeKey: Bool {
        isExternal
    }

    /// Keys reach `onKey` before any control, so a focused button never takes Space or Esc.
    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, let onKey, onKey(event) {
            return
        }
        super.sendEvent(event)
    }

    override var canBecomeMain: Bool {
        false
    }
}

/// The panel's content: the file name, then the mini player at full size.
struct QuickPreviewView: View {
    let preview: PreviewModel
    let onToggleFullScreen: () -> Void
    let onInfo: () -> Void
    let onOpenInViewer: () -> Void

    @State private var isFullScreen = false

    var body: some View {
        VStack(spacing: JGSpacing.s) {
            Text(verbatim: preview.asset?.name ?? "")
                .jgTextStyle(.body)
                .foregroundStyle(JGColor.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(height: JGMetrics.controlHeightCompact)
                .padding(.horizontal, JGMetrics.windowControlsInset)
                .frame(maxWidth: .infinity)
                .overlay(alignment: .trailing) {
                    if preview.asset != nil {
                        HStack(spacing: 0) {
                            ViewerIconButton(
                                symbol: "arrow.up.forward.square",
                                label: Text("Open in Viewer", comment: "Quick Preview: opens the file in the full viewer"),
                                action: onOpenInViewer
                            )
                            ViewerIconButton(symbol: "info.circle", label: Text("Get Info", comment: "Action"), action: onInfo)
                        }
                    }
                }
            if let asset = preview.asset {
                MiniPlayer(
                    preview: preview, asset: asset, style: .quickPreview,
                    fullScreen: .init(isOn: isFullScreen, toggle: onToggleFullScreen)
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding([.horizontal, .bottom], JGSpacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            ZStack {
                Rectangle().fill(isFullScreen ? JGColor.bgMedia : JGColor.bgRaised)
                if preview.asset?.kind == .audio {
                    CoverBackdropView(cover: preview.cover)
                }
            }
        }
        .ignoresSafeArea()
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didEnterFullScreenNotification)) { note in
            if note.object is QuickPreviewPanel {
                isFullScreen = true
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didExitFullScreenNotification)) { note in
            if note.object is QuickPreviewPanel {
                isFullScreen = false
            }
        }
    }
}
