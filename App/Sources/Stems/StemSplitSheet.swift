import AppKit
import JGDesign
import JGStems
import SwiftUI

/// The Split into Stems window (D-97, as Windows W-85): where the stems go (a new "<song> split" folder next to the
/// song, or a chosen folder), 4 or 6 stems, a tick per stem (one stays ticked). A missing model is offered for
/// download first, with its size and Stop; nothing is downloaded without the click.
struct StemSplitSheet: View {
    let stems: StemsModel
    let songs: [URL]
    @State private var folder: URL?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        let mode = stems.choice.mode
        VStack(alignment: .leading, spacing: JGSpacing.m) {
            Text(title)
                .jgTextStyle(.heading)
                .foregroundStyle(JGColor.textPrimary)
            folderRow
            JGSegmented(
                selection: Binding(get: { stems.choice.mode }, set: { stems.choice = stems.choice.with(mode: $0) }),
                options: [
                    (.four, Text("4 Stems", comment: "Split into Stems: vocals, drums, bass, other")),
                    (.six, Text("6 Stems", comment: "Split into Stems: also guitar and piano")),
                ]
            )
            VStack(alignment: .leading, spacing: JGSpacing.xs) {
                ForEach(StemModelInfo.shown(mode), id: \.self) { stem in
                    Toggle(isOn: Binding(
                        get: { stems.choice.ticked.contains(stem) },
                        set: { stems.choice = stems.choice.with(stem, ticked: $0) }
                    )) {
                        Self.name(stem).jgTextStyle(.body)
                    }
                    .toggleStyle(.jgCheckbox)
                }
            }
            if !stems.isInstalled(stems.model(for: mode)) {
                StemModelOffer(stems: stems, model: stems.model(for: mode))
            }
            HStack {
                Spacer()
                Button(role: .cancel) { dismiss() } label: { Text("Cancel") }
                    .buttonStyle(.jg(.secondary))
                    .keyboardShortcut(.cancelAction)
                Button {
                    stems.split(songs, into: folder)
                    dismiss()
                } label: {
                    Text("Split", comment: "Split into Stems: starts splitting")
                }
                .buttonStyle(.jg(.primary))
                .keyboardShortcut(.defaultAction)
                .disabled(!stems.choice.canSplit || !stems.isInstalled(stems.model(for: mode)))
            }
        }
        .padding(JGSpacing.l)
        .frame(width: JGMetrics.batchRenameWidth)
        .background(JGColor.bgPanel)
    }

    private var title: String {
        songs.count == 1
            ? String(
                localized: "Split “\(songs[0].deletingPathExtension().lastPathComponent)” into Stems",
                comment: "Split into Stems: title; the argument is a song"
            )
            : String(localized: "Split \(songs.count) Songs into Stems", comment: "Split into Stems: title for several songs")
    }

    private var folderRow: some View {
        HStack(spacing: JGSpacing.s) {
            VStack(alignment: .leading, spacing: JGSpacing.xxs) {
                Text("Save To", comment: "Split into Stems: the target folder")
                    .jgTextStyle(.label)
                    .foregroundStyle(JGColor.textTertiary)
                Text(verbatim: folderDescription)
                    .jgTextStyle(.body)
                    .foregroundStyle(JGColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: JGSpacing.m)
            if folder != nil {
                Button { folder = nil } label: { Text("Next to the Song", comment: "Split into Stems: back to the default folder") }
                    .buttonStyle(.jg(.tertiary))
            }
            Button(action: chooseFolder) { Text("Choose…", comment: "Split into Stems: picks a folder") }
                .buttonStyle(.jg(.secondary))
        }
    }

    private var folderDescription: String {
        if let folder {
            return folder.path
        }
        guard songs.count == 1 else {
            return String(localized: "A new “… split” folder next to each song", comment: "Split into Stems: default for several songs")
        }
        return StemNaming.defaultFolder(for: songs[0]) { FileManager.default.fileExists(atPath: $0.path) }.path
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = songs.first?.deletingLastPathComponent()
        panel.prompt = String(localized: "Choose", comment: "Folder panel button")
        if panel.runModal() == .OK {
            folder = panel.url
        }
    }

    static func name(_ stem: StemKind) -> Text {
        switch stem {
        case .vocals: Text("Vocals", comment: "Stem")
        case .drums: Text("Drums", comment: "Stem")
        case .bass: Text("Bass", comment: "Stem")
        case .guitar: Text("Guitar", comment: "Stem")
        case .piano: Text("Piano", comment: "Stem")
        case .other: Text("Other", comment: "Stem: everything else")
        }
    }
}

/// "The 4-stem model (103 MB) is downloaded once" with Download, or its progress with Stop.
struct StemModelOffer: View {
    let stems: StemsModel
    let model: StemModelInfo

    var body: some View {
        let mode = model.mode
        let total = StemModelStore.source(for: model).bytes
        let size = ByteCountFormatter.string(fromByteCount: total, countStyle: .file)
        VStack(alignment: .leading, spacing: JGSpacing.xs) {
            VStack(alignment: .leading, spacing: JGSpacing.xxs) {
                Text(mode == .four
                    ? String(
                        localized: "Splitting needs the 4-stem model (\(size)), downloaded once.",
                        comment: "Split into Stems: model offer"
                    )
                    : String(
                        localized: "Splitting needs the 6-stem model (\(size)), downloaded once.",
                        comment: "Split into Stems: model offer"
                    ))
                    .foregroundStyle(JGColor.textPrimary)
                Text(
                    "From github.com/volodya88i/jGlancer-models. Your music never leaves this Mac.",
                    comment: "Split into Stems: model source"
                )
                .foregroundStyle(JGColor.textSecondary)
            }
            .jgTextStyle(.body)
            .fixedSize(horizontal: false, vertical: true)
            if let received = stems.downloads[model.name] {
                HStack(spacing: JGSpacing.s) {
                    ProgressView(value: Double(received), total: Double(max(total, 1)))
                        .tint(JGColor.accent)
                    Button { stems.stopDownload(model) } label: { Text("Stop", comment: "Toast: stops a running file operation") }
                        .buttonStyle(.jg(.secondary))
                }
            } else {
                Button { stems.download(model) } label: { Text("Download", comment: "Split into Stems: downloads the model") }
                    .buttonStyle(.jg(.primary))
            }
            if let error = stems.downloadError {
                Text(verbatim: error)
                    .jgTextStyle(.body)
                    .foregroundStyle(JGColor.danger)
            }
        }
        .padding(JGSpacing.s)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(JGColor.bgRaised, in: JGShape(.medium))
    }
}

/// The card at the bottom of the window while songs are split: the song, percent, time left, songs waiting, Stop.
struct StemProgressCard: View {
    let stems: StemsModel

    var body: some View {
        if let running = stems.running {
            HStack(spacing: JGSpacing.m) {
                Image(systemName: "waveform.path")
                    .foregroundStyle(JGColor.accentText)
                VStack(alignment: .leading, spacing: JGSpacing.xxs) {
                    Text(String(
                        localized: "Splitting “\(running.job.song.deletingPathExtension().lastPathComponent)”",
                        comment: "Stem progress card; the argument is a song"
                    ))
                    .jgTextStyle(.body)
                    .foregroundStyle(JGColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    Text(verbatim: detail(running))
                        .jgTextStyle(.mono)
                        .foregroundStyle(JGColor.textSecondary)
                }
                ProgressView(value: running.progress)
                    .tint(JGColor.accent)
                    .frame(width: JGMetrics.sidebarWidth / 2)
                Button { stems.stop() } label: { Text("Stop", comment: "Toast: stops a running file operation") }
                    .buttonStyle(.jg(.secondary))
            }
            .padding(JGSpacing.m)
            .jgPanelBackground(JGColor.bgRaised, in: JGShape(.medium))
            .overlay(JGShape(.medium).strokeBorder(JGColor.lineHair, lineWidth: JGMetrics.outlineWidth))
        }
    }

    private func detail(_ running: StemsModel.Running) -> String {
        var parts = ["\(Int(running.progress * 100)) %"]
        if let left = stems.secondsLeft {
            parts.append(String(localized: "\(Int(left.rounded())) s left", comment: "Stem progress: time left in seconds"))
        }
        if !stems.waiting.isEmpty {
            parts.append(String(localized: "\(stems.waiting.count) waiting", comment: "Stem progress: songs queued"))
        }
        return parts.joined(separator: " · ")
    }
}
