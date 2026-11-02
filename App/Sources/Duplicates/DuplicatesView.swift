import AppKit
import JGDesign
import JGModel
import JGThumbs
import SwiftUI

/// The Find Duplicates window (W-78): a summary with "Move N to Trash" over the groups, biggest first; each copy
/// has a tick, its thumbnail, name, folder and date. A double-click shows the copy in the library.
struct DuplicatesView: View {
    let appModel: AppModel
    @State private var model: DuplicatesModel?
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Group {
            if let model {
                DuplicatesContent(model: model) { asset in
                    appModel.showInLibrary(asset.id)
                    openWindow(id: SceneID.main)
                }
            } else {
                Color.clear
            }
        }
        .frame(minWidth: JGMetrics.windowMinWidth / 2, minHeight: JGMetrics.windowMinHeight / 2)
        .background(JGColor.bgBase)
        .task {
            guard model == nil, let library = appModel.library else { return }
            let model = DuplicatesModel(store: library.store, thumbnails: library.thumbnails)
            let fileOps = appModel.fileOps
            model.onTrash = { urls in fileOps?.trash(urls) }
            self.model = model
            await model.scan()
        }
    }
}

private struct DuplicatesContent: View {
    let model: DuplicatesModel
    let onShow: (Asset) -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            JGHairline()
            if model.plan.groups.isEmpty {
                JGEmptyState(
                    title: AttributedString(
                        localized: "No **copies**.",
                        comment: "Find Duplicates: nothing found; ** marks the accent word"
                    ),
                    message: Text("No two files have the same contents.", comment: "Find Duplicates: nothing found"),
                    isLarge: false
                ) {
                    EmptyView()
                }
                .padding(JGSpacing.xxl)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: JGSpacing.m) {
                        ForEach(model.plan.groups) { group in
                            DuplicateGroupView(model: model, group: group, onShow: onShow)
                        }
                    }
                    .padding(JGSpacing.m)
                }
            }
        }
    }

    private var header: some View {
        HStack(spacing: JGSpacing.m) {
            VStack(alignment: .leading, spacing: JGSpacing.xxs) {
                Text(summary)
                    .jgTextStyle(.body)
                    .foregroundStyle(JGColor.textPrimary)
                if model.pending > 0 {
                    Text("\(model.pending) files still being read; they may hide more copies.",
                         comment: "Find Duplicates: files whose fingerprint is not read yet; the argument is a count")
                        .jgTextStyle(.body)
                        .foregroundStyle(JGColor.textTertiary)
                }
                if let message = model.message {
                    Text(verbatim: message)
                        .jgTextStyle(.body)
                        .foregroundStyle(JGColor.textSecondary)
                }
            }
            Spacer(minLength: JGSpacing.m)
            Button {
                Task { await model.scan() }
            } label: {
                Text("Refresh", comment: "Find Duplicates: looks again")
            }
            .buttonStyle(.jg(.secondary))
            .disabled(model.isScanning || model.isTrashing)
            Button {
                Task { await model.moveTickedToTrash() }
            } label: {
                Text("Move \(model.plan.ticked.count) to Trash", comment: "Find Duplicates: the argument is the number of ticked copies")
            }
            .buttonStyle(.jg(.primary))
            .disabled(model.plan.ticked.isEmpty || model.isTrashing)
        }
        .padding(JGSpacing.m)
    }

    private var summary: String {
        let bytes = ByteCountFormatter.string(fromByteCount: model.plan.tickedBytes, countStyle: .file)
        return String(
            localized: "\(model.plan.groups.count) groups · \(model.plan.extraCopies) extra copies · \(bytes) ticked",
            comment: "Find Duplicates summary: groups, copies beyond one per group, size of the ticked copies"
        )
    }
}

/// One group: "N copies · size", then a row per copy.
private struct DuplicateGroupView: View {
    let model: DuplicatesModel
    let group: DuplicatePlan.Group
    let onShow: (Asset) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: JGSpacing.xxs) {
            let size = ByteCountFormatter.string(fromByteCount: group.copies.first?.size ?? 0, countStyle: .file)
            JGSectionHeader(Text("\(group.copies.count) copies · \(size)", comment: "Find Duplicates group header; shown in capitals"))
            ForEach(group.copies) { copy in
                DuplicateRow(model: model, copy: copy)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { onShow(copy) }
            }
        }
    }
}

private struct DuplicateRow: View {
    let model: DuplicatesModel
    let copy: Asset
    @State private var thumbnail: CGImage?

    var body: some View {
        HStack(spacing: JGSpacing.s) {
            Toggle(isOn: Binding(get: { model.plan.isTicked(copy.id) }, set: { _ in
                if !model.toggle(copy.id) {
                    NSSound.beep()
                }
            })) {
                EmptyView()
            }
            .toggleStyle(.jgCheckbox)
            .accessibilityLabel(Text(verbatim: copy.name))
            Group {
                if let thumbnail {
                    Image(decorative: thumbnail, scale: 1).resizable().scaledToFill()
                } else {
                    JGShape(.small).fill(JGColor.bgRaised)
                }
            }
            .frame(width: JGMetrics.duplicateThumbnailSide, height: JGMetrics.duplicateThumbnailSide)
            .clipShape(JGShape(.small))
            VStack(alignment: .leading, spacing: JGSpacing.xxs) {
                Text(verbatim: copy.name)
                    .jgTextStyle(.body)
                    .foregroundStyle(JGColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(verbatim: copy.url.deletingLastPathComponent().path)
                    .jgTextStyle(.body)
                    .foregroundStyle(JGColor.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
            Spacer(minLength: JGSpacing.m)
            Text(copy.createdAt ?? copy.modifiedAt, format: .dateTime.year().month().day().hour().minute())
                .jgTextStyle(.mono)
                .foregroundStyle(JGColor.textSecondary)
        }
        .padding(.horizontal, JGSpacing.xs)
        .task(id: copy.id) { await loadThumbnail() }
    }

    private func loadThumbnail() async {
        let request = ThumbnailRequest(
            assetID: copy.id, url: copy.url, kind: copy.kind, typeIdentifier: copy.typeIdentifier,
            modifiedAt: copy.modifiedAt, duration: copy.duration, bucket: .small
        )
        if let cached = model.thumbnails.cachedThumbnail(for: request) {
            thumbnail = cached
            return
        }
        thumbnail = await model.thumbnails.thumbnail(for: request, priority: .visible)
    }
}
