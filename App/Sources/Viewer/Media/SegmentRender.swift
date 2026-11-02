import AppKit
import JGPlayback
import UniformTypeIdentifiers

/// One export of a segment into a private temporary folder, started at once and shared by whoever needs the file
/// (D-74): a drag (as a file or a promise), Save As, Edit In. The temporary folder is left to macOS to clear.
final class SegmentRender: @unchecked Sendable {
    let request: SegmentExportRequest
    /// The file's name, "Name (1m02.0s–1m15.4s).ext".
    let name: String
    private let task: Task<URL, Error>

    init(request: SegmentExportRequest) {
        self.request = request
        name = SegmentExporter.suggestedName(for: request)
        let target = FileManager.default.temporaryDirectory
            .appendingPathComponent("jGlancer-segments/\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent(name)
        task = Task.detached(priority: .userInitiated) {
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            return try await SegmentExporter.save(request, to: target)
        }
    }

    var contentType: UTType? {
        Self.contentType(for: request)
    }

    static func contentType(for request: SegmentExportRequest) -> UTType? {
        UTType(filenameExtension: SegmentExporter.fileExtension(for: request))
    }

    func file() async throws -> URL {
        try await task.value
    }

    /// Waits for the file on this thread (pasteboard requests are answered synchronously); nil on failure or after
    /// `timeout` seconds.
    func fileNow(timeout: Double) -> URL? {
        let result = RenderResult()
        let done = DispatchSemaphore(value: 0)
        Task.detached { [task] in
            result.url = try? await task.value
            done.signal()
        }
        return done.wait(timeout: .now() + timeout) == .success ? result.url : nil
    }

    /// A copy at `url`, or at "Name 2.ext"… when something is there already (nothing is replaced).
    @discardableResult
    func copy(to url: URL) async throws -> URL {
        let file = try await file()
        let target = SegmentExporter.vacant(url)
        try FileManager.default.copyItem(at: file, to: target)
        return target
    }
}

/// The rendered file, handed from the waiting task to the waiting thread (the semaphore orders the two).
private final class RenderResult: @unchecked Sendable {
    var url: URL?
}

/// Save As… and Edit In for a segment (D-74).
@MainActor
enum SegmentSaving {
    /// A save panel; the segment is written where the user says. A file the user agreed to replace goes to the
    /// Trash first (never deleted).
    static func saveAs(_ render: SegmentRender) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = render.name
        panel.allowedContentTypes = render.contentType.map { [$0] } ?? []
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        let save = { (response: NSApplication.ModalResponse) in
            guard response == .OK, let url = panel.url else { return }
            Task {
                do {
                    if FileManager.default.fileExists(atPath: url.path) {
                        try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                    }
                    try await render.copy(to: url)
                } catch {
                    NSApp.presentError(error)
                }
            }
        }
        if let window = NSApp.keyWindow {
            panel.beginSheetModal(for: window, completionHandler: save)
        } else {
            save(panel.runModal())
        }
    }

    /// Opens a copy of the segment in `app` (kept in Application Support ▸ Edited Segments).
    static func edit(_ render: SegmentRender, in app: URL) {
        Task {
            do {
                let folder = AppPaths.editedSegments
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                let copy = try await render.copy(to: folder.appendingPathComponent(render.name))
                _ = try await NSWorkspace.shared.open([copy], withApplicationAt: app, configuration: NSWorkspace.OpenConfiguration())
            } catch {
                NSApp.presentError(error)
            }
        }
    }

    /// Any app, from a panel opened at /Applications.
    static func editInOtherApp(_ render: SegmentRender) {
        let panel = NSOpenPanel()
        panel.directoryURL = URL(fileURLWithPath: "/Applications", isDirectory: true)
        panel.allowedContentTypes = [.application]
        panel.prompt = String(localized: "Edit", comment: "Edit In ▸ Other…: the panel's button")
        guard panel.runModal() == .OK, let app = panel.url else { return }
        edit(render, in: app)
    }
}
