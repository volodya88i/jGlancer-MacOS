import JGDesign
import JGModel
import JGSettings
import JGStems
import SwiftUI

/// Settings → Library: the folders, image sequences, the preview, the thumbnail cache (cap, size, Clear Cache) and
/// the stem splitter's models (size, Download or Remove; D-97).
struct LibrarySettings: View {
    let appModel: AppModel
    @State private var usedBytes: Int64?
    @State private var rootToRemove: RootFolder?

    var body: some View {
        SettingsGroup(title: Text("Folders", comment: "Sidebar section label; shown in capitals")) {
            ForEach(appModel.library?.roots ?? [], id: \.id) { root in
                HStack(spacing: JGSpacing.xs) {
                    Image(systemName: "externaldrive")
                        .foregroundStyle(JGColor.textSecondary)
                    Text(verbatim: root.path)
                        .jgTextStyle(.body)
                        .foregroundStyle(JGColor.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button { rootToRemove = root } label: {
                        Image(systemName: "minus.circle").foregroundStyle(JGColor.textSecondary)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Remove from Library", comment: "Context menu item; files are not touched"))
                }
                .frame(height: JGMetrics.controlHeightCompact)
            }
            Button {
                Task { await appModel.library?.addFolders(FolderPicker.chooseFolders()) }
            } label: {
                Text("Add Folder…")
            }
            .buttonStyle(.jg(.secondary))
        }
        SettingsGroup(title: Text("Image Sequences", comment: "Settings group; shown in capitals")) {
            SettingsToggle(
                title: Text(
                    "Fold numbered frames (render_001…090) into one tile",
                    comment: "Settings: image sequences in a folder show as one tile"
                ),
                isOn: appModel.settingsStore.settings.foldsSequences
            ) { isOn in appModel.settingsStore.update { $0.foldsSequences = isOn } }
        }
        SettingsGroup(title: Text("Preview", comment: "Section label of the preview pane; shown in capitals")) {
            SettingsToggle(
                title: Text("Show camera, codec and other details", comment: "Settings: extended facts in the preview pane"),
                isOn: appModel.settingsStore.settings.previewDetails
            ) { isOn in appModel.settingsStore.update { $0.previewDetails = isOn } }
        }
        SettingsGroup(title: Text("Thumbnail Cache", comment: "Settings group; shown in capitals")) {
            HStack(spacing: JGSpacing.s) {
                Picker(selection: Binding(
                    get: { appModel.settingsStore.settings.thumbnailCacheGigabytes },
                    set: { gigabytes in appModel.settingsStore.update { $0.thumbnailCacheGigabytes = gigabytes } }
                )) {
                    ForEach(AppSettings.cacheChoices, id: \.self) { gigabytes in
                        Text(verbatim: ByteCountFormatter.string(fromByteCount: Int64(gigabytes) << 30, countStyle: .memory)).tag(gigabytes)
                    }
                } label: {
                    Text("At most", comment: "Settings: thumbnail cache cap")
                        .jgTextStyle(.body)
                        .foregroundStyle(JGColor.textSecondary)
                }
                .fixedSize()
                // Binary units, like the limit (the cap is in GiB).
                Text(verbatim: usedBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .memory) } ?? "…")
                    .jgTextStyle(.body)
                    .foregroundStyle(JGColor.textSecondary)
                Spacer()
                Button {
                    Task {
                        try? await appModel.library?.thumbnails.removeAll()
                        await refreshUsage()
                    }
                } label: {
                    Text("Clear Cache", comment: "Settings: deletes cached thumbnails")
                }
                .buttonStyle(.jg(.secondary))
            }
        }
        .task { await refreshUsage() }
        SettingsGroup(title: Text("Stem Splitting", comment: "Settings group; shown in capitals")) {
            JGSegmented(
                selection: Binding(get: { appModel.stems.usesFullModel }, set: { appModel.stems.usesFullModel = $0 }),
                options: [
                    (false, Text("Compact", comment: "Settings: the stem model with half-precision weights")),
                    (true, Text("Full", comment: "Settings: the stem model with the original weights")),
                ]
            )
            Text("They sound the same; Compact takes half the space on disk.", comment: "Settings: compact and full stem models")
                .jgTextStyle(.body)
                .foregroundStyle(JGColor.textTertiary)
            ForEach(StemModelInfo.all, id: \.name) { model in
                StemModelRow(stems: appModel.stems, model: model)
            }
        }
        .confirmationDialog(
            Text("Remove “\(rootToRemove.map { ($0.path as NSString).lastPathComponent } ?? "")” from the library?"),
            isPresented: Binding(get: { rootToRemove != nil }, set: {
                if !$0 {
                    rootToRemove = nil
                }
            }),
            presenting: rootToRemove
        ) { root in
            Button(role: .destructive) {
                Task { await appModel.library?.removeRoot(root.id) }
            } label: {
                Text("Remove from Library", comment: "Context menu item; files are not touched")
            }
        }
    }

    private func refreshUsage() async {
        usedBytes = try? await appModel.settingsStore.thumbnailCache?.usedBytes()
    }
}

/// Settings → Playback: Quick Preview autoplay, Keep Pitch ("play next" is a button in the players, D-72).
struct PlaybackSettings: View {
    let appModel: AppModel

    var body: some View {
        let store = appModel.settingsStore
        SettingsGroup(title: Text("Playback", comment: "Settings section")) {
            SettingsToggle(
                title: Text("Play video and audio in Quick Preview", comment: "Settings: autoplay in Quick Preview"),
                isOn: store.settings.autoplayInPreview
            ) { isOn in store.update { $0.autoplayInPreview = isOn } }
            SettingsToggle(
                title: Text(
                    "Keep WAV, AIFF and FLAC segments in their format (otherwise M4A)",
                    comment: "Settings: exported audio segments keep the lossless format of their file"
                ),
                isOn: store.settings.segmentKeepsAudioFormat
            ) { isOn in store.update { $0.segmentKeepsAudioFormat = isOn } }
            SettingsToggle(
                title: Text(
                    "Cut video exactly at the brackets (encodes it again)",
                    comment: "Settings: video segments are encoded again so they start and end exactly at the brackets"
                ),
                isOn: store.settings.segmentCutsExactly
            ) { isOn in store.update { $0.segmentCutsExactly = isOn } }
            SettingsToggle(
                title: Text(
                    "The mouse wheel zooms the timeline of a segment (otherwise ⌘ and the wheel)",
                    comment: "Settings: in segment selection the plain mouse wheel zooms"
                ),
                isOn: store.settings.wheelZoomsTimeline
            ) { isOn in store.update { $0.wheelZoomsTimeline = isOn } }
            SettingsToggle(
                title: Text("Keep Pitch", comment: "Player: keep the pitch when the speed changes"),
                isOn: appModel.playback.preservesPitch
            ) { isOn in appModel.tuning.setPreservesPitch(isOn) }
        }
    }
}

/// A stem model in Settings: its name, size on disk, and Remove; or Download with its progress.
private struct StemModelRow: View {
    let stems: StemsModel
    let model: StemModelInfo

    private var name: String {
        switch (model.mode, model.isFull) {
        case (.four, true): String(localized: "4 stems, Full", comment: "Settings: a stem model")
        case (.six, true): String(localized: "6 stems, Full", comment: "Settings: a stem model")
        case (.four, false): String(localized: "4 stems, Compact", comment: "Settings: a stem model")
        case (.six, false): String(localized: "6 stems, Compact", comment: "Settings: a stem model")
        }
    }

    var body: some View {
        HStack(spacing: JGSpacing.s) {
            Text(verbatim: name)
                .jgTextStyle(.body)
                .foregroundStyle(JGColor.textPrimary)
            if stems.isInstalled(model) {
                Text(verbatim: ByteCountFormatter.string(fromByteCount: stems.store.installedBytes(model), countStyle: .file))
                    .jgTextStyle(.body)
                    .foregroundStyle(JGColor.textSecondary)
                Spacer()
                Button { stems.remove(model) } label: { Text("Remove", comment: "Confirms removing a folder from the library") }
                    .buttonStyle(.jg(.secondary))
            } else if let received = stems.downloads[model.name] {
                Spacer()
                ProgressView(value: Double(received), total: Double(max(StemModelStore.source(for: model).bytes, 1)))
                    .tint(JGColor.accent)
                    .frame(width: JGMetrics.sidebarWidth / 2)
                Button { stems.stopDownload(model) } label: { Text("Stop", comment: "Toast: stops a running file operation") }
                    .buttonStyle(.jg(.secondary))
            } else {
                Text(verbatim: ByteCountFormatter.string(fromByteCount: StemModelStore.source(for: model).bytes, countStyle: .file))
                    .jgTextStyle(.body)
                    .foregroundStyle(JGColor.textTertiary)
                Spacer()
                Button { stems.download(model) } label: { Text("Download", comment: "Split into Stems: downloads the model") }
                    .buttonStyle(.jg(.secondary))
            }
        }
        .frame(height: JGMetrics.controlHeightCompact)
    }
}
