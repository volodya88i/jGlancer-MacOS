import AppKit
import JGDesign
import Observation

/// The folded sidebar opening over the files (D-128): the pointer resting on the strip opens it, leaving it closes it
/// a moment later. It stays while something started in it is still open: a menu (a row's context menu), a sheet
/// (Remove from Library's question) or a name being edited, and closes when that ends if the pointer has left.
@MainActor
@Observable
final class SidebarPeek {
    private(set) var isOpen = false
    /// The library window, and the sidebar's width over the files (it runs from the window's left edge).
    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored var width: CGFloat = 0
    @ObservationIgnored private var opening: Task<Void, Never>?
    @ObservationIgnored private var closing: Task<Void, Never>?
    @ObservationIgnored private var isMenuOpen = false
    @ObservationIgnored private var isSuppressed = false
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    init() {
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSMenu.didBeginTrackingNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.isMenuOpen = true }
        })
        let ends: [NSNotification.Name] = [
            NSMenu.didEndTrackingNotification, NSWindow.didEndSheetNotification, NSControl.textDidEndEditingNotification,
        ]
        for name in ends {
            observers.append(center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated {
                    if name == NSMenu.didEndTrackingNotification {
                        self?.isMenuOpen = false
                    }
                    self?.closeIfLeft()
                }
            })
        }
    }

    /// The pointer on the folded sidebar. `onTrigger`: where resting opens it (under the top bar and the button), or
    /// anywhere once it is open. Opens only in the active window (crossing a window in the background opens nothing;
    /// files dragged from another app still open it, `open()`), and not again before the pointer has left the panel
    /// after the sidebar was folded under it.
    func pointer(inPanel: Bool, onTrigger: Bool) {
        guard inPanel else {
            cancelOpening()
            isSuppressed = false
            scheduleClose()
            return
        }
        closing?.cancel()
        guard onTrigger else {
            cancelOpening()
            return
        }
        guard !isOpen, !isSuppressed, opening == nil, window?.isKeyWindow ?? true else { return }
        opening = Task { [weak self] in
            try? await Task.sleep(for: .seconds(JGMetrics.sidebarPeekOpenDelay))
            guard let self, !Task.isCancelled else { return }
            opening = nil
            isOpen = true
        }
    }

    /// Folded under the pointer (Hide Sidebar, ⌥⌘S): it does not open again until the pointer leaves it.
    func suppressUntilExit() {
        cancelOpening()
        isSuppressed = true
    }

    private func cancelOpening() {
        opening?.cancel()
        opening = nil
    }

    /// At once: files dragged onto the strip, to be dropped on a folder or an album.
    func open() {
        cancelOpening()
        closing?.cancel()
        isOpen = true
    }

    func close() {
        cancelOpening()
        closing?.cancel()
        isOpen = false
    }

    private func scheduleClose() {
        closing?.cancel()
        guard isOpen else { return }
        closing = Task { [weak self] in
            try? await Task.sleep(for: .seconds(JGMetrics.sidebarPeekCloseDelay))
            guard let self, !Task.isCancelled, !isHeld, !isPointerInside else { return }
            isOpen = false
        }
    }

    /// After a menu, a sheet or an edit ends: closes unless the pointer is back on the sidebar.
    private func closeIfLeft() {
        guard isOpen, !isPointerInside else { return }
        scheduleClose()
    }

    private var isHeld: Bool {
        isMenuOpen || window?.attachedSheet != nil || isEditingInside
    }

    /// Where the pointer is now, in the window (not from hover, which goes quiet under a menu or a sheet).
    private var isPointerInside: Bool {
        guard let window else { return false }
        let point = window.mouseLocationOutsideOfEventStream
        return point.x >= 0 && point.x < width && point.y >= 0 && point.y <= window.frame.height
    }

    /// A text field of the sidebar (an album's name) is being edited.
    private var isEditingInside: Bool {
        guard let editor = window?.firstResponder as? NSTextView, editor.isFieldEditor else { return false }
        return editor.convert(editor.bounds, to: nil).minX < width
    }
}
