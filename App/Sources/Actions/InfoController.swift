import AppKit
import JGDesign
import JGModel
import JGScanner
import JGStore
import SwiftUI

/// Get Info (basic, docs/PLAN.md Phase 6): a small panel with the facts of one file, or the count and size of
/// several. Library files use their rows; other files their file-system attributes.
@MainActor
final class InfoController {
    private var panel: NSPanel?

    func show(_ target: ActionTarget, store: LibraryStore?, analyses: AudioAnalyses?) async {
        let entries: [InfoEntry] = if !target.assetIDs.isEmpty, let store {
            await ((try? store.assets(ids: target.assetIDs)) ?? []).map(InfoEntry.init(asset:))
        } else {
            await target.urls().map(InfoEntry.init(url:))
        }
        guard !entries.isEmpty else { return }
        // Tempo and key, once the audio player found them (D-106).
        var analysis: AudioAnalysis?
        if entries.count == 1, let entry = entries.first, entry.kind == .audio {
            analysis = await analyses?.known(URL(fileURLWithPath: entry.path))
        }
        let panel = panel ?? makePanel()
        self.panel = panel
        // The panel follows the content's size, so it grows when the extended facts arrive.
        let controller = NSHostingController(rootView: InfoView(entries: entries, analysis: analysis))
        controller.sizingOptions = .preferredContentSize
        panel.contentViewController = controller
        panel.makeKeyAndOrderFront(nil)
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: JGMetrics.previewPaneMinWidth, height: 200),
            styleMask: [.titled, .closable, .utilityWindow, .fullSizeContentView], backing: .buffered, defer: true
        )
        panel.title = String(localized: "Get Info", comment: "Action")
        panel.titlebarAppearsTransparent = true
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = true
        panel.isReleasedWhenClosed = false
        panel.center()
        panel.setFrameAutosaveName("GetInfo")
        return panel
    }
}

/// The facts shown for one file.
struct InfoEntry: Equatable {
    let name: String
    let path: String
    let kind: MediaKind?
    let size: Int64
    let dimensions: String?
    let duration: Double?
    let created: Date?
    let modified: Date?
    let captured: Date?

    init(asset: Asset) {
        name = asset.name
        path = asset.url.path
        kind = asset.kind
        size = asset.size
        dimensions = asset.width.flatMap { width in asset.height.map { "\(width) × \($0)" } }
        duration = asset.duration
        created = asset.createdAt
        modified = asset.modifiedAt
        captured = asset.capturedAt
    }

    init(url: URL) {
        let values = try? url.resourceValues(forKeys: [.fileSizeKey, .creationDateKey, .contentModificationDateKey])
        name = url.lastPathComponent
        path = url.path
        kind = MediaClassifier().classify(fileName: url.lastPathComponent)?.kind
        size = Int64(values?.fileSize ?? 0)
        dimensions = nil
        duration = nil
        created = values?.creationDate
        modified = values?.contentModificationDate
        captured = nil
    }
}

/// Labels in the label style, values in mono (docs/DESIGN.md §4).
struct InfoView: View {
    let entries: [InfoEntry]
    var analysis: AudioAnalysis?

    var body: some View {
        VStack(alignment: .leading, spacing: JGSpacing.s) {
            if entries.count == 1, let entry = entries.first {
                Text(verbatim: entry.name)
                    .jgTextStyle(.heading)
                    .foregroundStyle(JGColor.textPrimary)
                    .lineLimit(3)
                    .textSelection(.enabled)
                facts(for: entry)
            } else {
                Text(verbatim: "\(entries.count)")
                    .jgTextStyle(.display)
                    .foregroundStyle(JGColor.textPrimary)
                row(
                    Text("Selected", comment: "Preview pane: label under the number of selected files; shown in capitals"),
                    size(entries.map(\.size).reduce(0, +))
                )
            }
        }
        .padding(JGSpacing.l)
        .padding(.top, JGSpacing.m)
        .frame(width: JGMetrics.previewPaneMaxWidth, alignment: .leading)
        .background(JGColor.bgPanel)
    }

    @ViewBuilder
    private func facts(for entry: InfoEntry) -> some View {
        row(Text("Size", comment: "Get Info label"), size(entry.size))
        detailed(entry)
        if let captured = entry.captured {
            row(Text("Taken", comment: "Get Info label: capture date"), date(captured))
        }
        if let modified = entry.modified {
            row(Text("Modified", comment: "Get Info label"), date(modified))
        }
        full(entry)
        // Camera, exposure, codecs and rates, read from the file (Phase 12).
        if let kind = entry.kind {
            MediaDetailsSection(url: URL(fileURLWithPath: entry.path), kind: kind)
                .padding(.top, JGSpacing.xs)
        }
    }

    @ViewBuilder
    private func detailed(_ entry: InfoEntry) -> some View {
        if let dimensions = entry.dimensions {
            row(Text("Dimensions", comment: "Get Info label"), dimensions)
        }
        if let duration = entry.duration, let text = DurationFormat.positional(duration) {
            row(Text("Duration", comment: "Get Info label"), text)
        }
        if let bpm = analysis?.bpmLabel {
            row(Text("BPM", comment: "Key and tempo panel: the song's tempo"), bpm)
        }
        if let key = analysis?.key {
            row(Text("Key", comment: "Key and tempo panel: the song's key"), key.label)
        }
    }

    @ViewBuilder
    private func full(_ entry: InfoEntry) -> some View {
        if let created = entry.created {
            row(Text("Created", comment: "Get Info label"), date(created))
        }
        row(Text("Where", comment: "Get Info label: the file's folder"), (entry.path as NSString).deletingLastPathComponent)
    }

    private func row(_ label: Text, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: JGSpacing.xxs) {
            label
                .jgTextStyle(.label)
                .foregroundStyle(JGColor.textTertiary)
            Text(verbatim: value)
                .jgTextStyle(.mono)
                .foregroundStyle(JGColor.textPrimary)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func size(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private func date(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }
}
