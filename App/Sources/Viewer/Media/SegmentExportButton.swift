import AppKit
import JGDesign
import JGPlayback
import SwiftUI
import UniformTypeIdentifiers

/// The players' export button (D-73, D-74, D-107): the segment while one is chosen, else the whole file. Pressing it
/// starts rendering; dragged to Finder or any app it delivers the file (as a file, for apps like Telegram, and as a
/// promise, for Finder); a click opens Save As. Disabled (dimmed) without `request`.
struct SegmentExportButton: NSViewRepresentable {
    let request: SegmentExportRequest?
    var isWhole = false

    func makeNSView(context _: Context) -> SegmentDragView {
        SegmentDragView()
    }

    func updateNSView(_ view: SegmentDragView, context _: Context) {
        view.request = request
        let label = Self.label(isAvailable: request != nil, isWhole: isWhole)
        view.toolTip = label
        view.setAccessibilityLabel(label)
        view.alphaValue = request == nil ? JGMetrics.placeholderOpacity : 1
    }

    private static func label(isAvailable: Bool, isWhole: Bool) -> String {
        switch (isAvailable, isWhole) {
        case (false, false):
            String(localized: "This file can't be cut.", comment: "Player: export button of a file that can't be cut (MKV)")
        case (false, true):
            String(localized: "This file can't be exported.", comment: "Player: export button of a video other than MP4 or MOV")
        case (true, false):
            String(localized: "Drag to export the segment, click to save it", comment: "Player: the segment export button")
        case (true, true):
            String(localized: "Drag to export the file, click to save it", comment: "Player: the export button without a segment")
        }
    }

    func sizeThatFits(_: ProposedViewSize, nsView _: SegmentDragView, context _: Context) -> CGSize? {
        CGSize(width: JGMetrics.controlHeight, height: JGMetrics.controlHeight)
    }
}

/// A drag source showing an arrow rising out of a tray.
final class SegmentDragView: NSView, NSDraggingSource {
    var request: SegmentExportRequest?
    private let icon = NSHostingView(rootView: AnyView(
        Image(systemName: "square.and.arrow.up")
            .font(.system(size: JGTextStyle.body.size))
            .foregroundStyle(JGColor.textPrimary)
            .accessibilityHidden(true)
    ))
    private var pressed: NSEvent?
    /// The segment being rendered since the button was pressed.
    private var render: SegmentRender?
    /// The promise of the drag in flight (its provider holds the delegate weakly).
    private var promise: SegmentPromise?

    override init(frame: NSRect) {
        super.init(frame: frame)
        addSubview(icon)
        setAccessibilityElement(true)
        setAccessibilityRole(.button)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        let size = icon.fittingSize
        icon.frame = CGRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width,
            height: size.height
        )
    }

    override var mouseDownCanMoveWindow: Bool {
        false
    }

    /// The whole button takes the mouse, not the icon inside it.
    override func hitTest(_ point: NSPoint) -> NSView? {
        frame.contains(point) ? self : nil
    }

    override func mouseDown(with event: NSEvent) {
        guard let request else { return }
        pressed = event
        if render?.request != request {
            render = SegmentRender(request: request)
        }
    }

    /// A click without a drag: Save As.
    override func mouseUp(with _: NSEvent) {
        guard pressed != nil, let render else { return }
        pressed = nil
        SegmentSaving.saveAs(render)
    }

    override func accessibilityPerformPress() -> Bool {
        guard let request else { return false }
        SegmentSaving.saveAs(render?.request == request ? render ?? SegmentRender(request: request) : SegmentRender(request: request))
        return true
    }

    override func mouseDragged(with _: NSEvent) {
        guard let render, let event = pressed else { return }
        pressed = nil
        let promise = SegmentPromise(render: render)
        self.promise = promise
        let provider = SegmentDragProvider(fileType: (render.contentType ?? .data).identifier, delegate: promise)
        provider.render = render
        let item = NSDraggingItem(pasteboardWriter: provider)
        item.setDraggingFrame(bounds, contents: snapshot())
        beginDraggingSession(with: [item], event: event, source: self)
    }

    func draggingSession(_: NSDraggingSession, sourceOperationMaskFor _: NSDraggingContext) -> NSDragOperation {
        .copy
    }

    private func snapshot() -> NSImage? {
        guard let rep = bitmapImageRepForCachingDisplay(in: bounds) else { return nil }
        cacheDisplay(in: bounds, to: rep)
        let image = NSImage(size: bounds.size)
        image.addRepresentation(rep)
        return image
    }
}

/// A file promise that also offers the rendered file itself: apps that take only files (Telegram, Mail…) get it
/// when they ask, which waits for the render if it is not done yet.
final class SegmentDragProvider: NSFilePromiseProvider {
    var render: SegmentRender?
    /// Long enough for a long segment at an unusual speed.
    static let renderTimeout = 60.0

    override func writableTypes(for pasteboard: NSPasteboard) -> [NSPasteboard.PasteboardType] {
        super.writableTypes(for: pasteboard) + [.fileURL]
    }

    override func writingOptions(forType type: NSPasteboard.PasteboardType, pasteboard: NSPasteboard) -> NSPasteboard.WritingOptions {
        type == .fileURL ? .promised : super.writingOptions(forType: type, pasteboard: pasteboard)
    }

    override func pasteboardPropertyList(forType type: NSPasteboard.PasteboardType) -> Any? {
        guard type == .fileURL else { return super.pasteboardPropertyList(forType: type) }
        return render?.fileNow(timeout: Self.renderTimeout).flatMap { ($0 as NSURL).pasteboardPropertyList(forType: .fileURL) }
    }
}

/// Makes the promised file where it was dropped: a copy of the render, never over an existing file.
final class SegmentPromise: NSObject, NSFilePromiseProviderDelegate, @unchecked Sendable {
    let render: SegmentRender
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.qualityOfService = .userInitiated
        return queue
    }()

    init(render: SegmentRender) {
        self.render = render
    }

    func filePromiseProvider(_: NSFilePromiseProvider, fileNameForType _: String) -> String {
        render.name
    }

    func operationQueue(for _: NSFilePromiseProvider) -> OperationQueue {
        queue
    }

    /// Runs on `queue`, which waits for the copy (the drop target shows the file as pending meanwhile).
    func filePromiseProvider(
        _: NSFilePromiseProvider, writePromiseTo url: URL, completionHandler: @escaping (Error?) -> Void
    ) {
        let outcome = ExportOutcome()
        let done = DispatchSemaphore(value: 0)
        let render = render
        Task.detached(priority: .userInitiated) {
            do {
                try await render.copy(to: url)
            } catch {
                outcome.error = error
            }
            done.signal()
        }
        done.wait()
        completionHandler(outcome.error)
    }
}

/// The copy's error, handed from the task to the waiting promise queue (the semaphore orders the two).
private final class ExportOutcome: @unchecked Sendable {
    var error: Error?
}
