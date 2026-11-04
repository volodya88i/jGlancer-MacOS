import AppKit
import JGDesign
import JGModel
import JGSettings
import SwiftUI

/// The selection preview on the right of the library (docs/FEATURES.md §2): the focused file in the mini player
/// with its name and facts, or the count and size of a multiple selection. Resizable by its left edge.
struct PreviewPane: View {
    let preview: PreviewModel
    let library: LibraryModel
    /// The pane whose selection is shown: the active one of a split view (D-89).
    var pane: LibraryModel?
    @Environment(\.appSettings) private var settings
    @Environment(\.settingsStore) private var settingsStore

    var body: some View {
        // The header row is as high as the top bar, so PREVIEW and the breadcrumb share a centre line (D-105).
        VStack(alignment: .leading, spacing: JGSpacing.xs) {
            HStack {
                JGSectionHeader(Text("Preview", comment: "Section label of the preview pane; shown in capitals"))
                Spacer()
                detailsButton
                closeButton
            }
            .frame(height: JGMetrics.barHeight)
            .background { Color.clear.contentShape(Rectangle()).titleBarDoubleClick() }
            content
                .padding(.bottom, JGSpacing.m)
        }
        .padding(.horizontal, JGSpacing.m)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack {
                Rectangle().fill(JGColor.bgPanel)
                if preview.selectionCount <= 1, preview.asset?.kind == .audio {
                    CoverBackdropView(cover: preview.cover)
                }
            }
        }
        .overlay(alignment: .leading) {
            PaneResizeHandle(width: library.state.previewWidth, growsTowardLeading: true, set: library.setPreviewWidth)
        }
    }

    /// Shows or hides the extended facts (also Settings → Library → Preview).
    private var detailsButton: some View {
        Button {
            settingsStore?.update { $0.previewDetails.toggle() }
        } label: {
            Image(systemName: settings.previewDetails ? "info.circle.fill" : "info.circle")
                .font(.system(size: JGTextStyle.body.size, weight: .medium))
                .foregroundStyle(settings.previewDetails ? JGColor.accentText : JGColor.textSecondary)
                .frame(width: JGMetrics.controlHeightCompact, height: JGMetrics.controlHeightCompact)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text("Camera, codec and other details", comment: "Preview pane: details button tooltip"))
        .accessibilityLabel(Text("Camera, codec and other details", comment: "Preview pane: details button tooltip"))
        .accessibilityAddTraits(settings.previewDetails ? .isSelected : [])
    }

    /// Hides the pane (View ▸ Show Preview, ⌥⌘0, brings it back).
    private var closeButton: some View {
        Button { library.setPreviewVisible(false) } label: {
            Image(systemName: "xmark")
                .font(.system(size: JGTextStyle.mono.size, weight: .semibold))
                .foregroundStyle(JGColor.textSecondary)
                .frame(width: JGMetrics.controlHeightCompact, height: JGMetrics.controlHeightCompact)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(Text("Hide Preview (⌥⌘0)", comment: "Preview pane: close button tooltip"))
        .accessibilityLabel(Text("Hide Preview", comment: "Preview pane: close button"))
    }

    @ViewBuilder
    private var content: some View {
        if preview.selectionCount > 1 {
            multiple
        } else if let asset = preview.asset {
            MiniPlayer(preview: preview, asset: asset, style: .pane)
                .frame(maxWidth: .infinity)
                .frame(maxHeight: .infinity)
            VStack(alignment: .leading, spacing: JGSpacing.xxs) {
                HStack(alignment: .firstTextBaseline, spacing: JGSpacing.xxs) {
                    Text(verbatim: asset.name)
                        .jgTextStyle(.body)
                        .foregroundStyle(JGColor.textPrimary)
                        .lineLimit(2)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                    FlagStar(assetID: asset.id)
                }
                Text(verbatim: PreviewFacts.line(for: asset))
                    .jgTextStyle(.mono)
                    .foregroundStyle(JGColor.textSecondary)
                Text(verbatim: PreviewFacts.date(for: asset))
                    .jgTextStyle(.mono)
                    .foregroundStyle(JGColor.textSecondary)
                if settings.previewDetails {
                    MediaDetailsSection(url: asset.url, kind: asset.kind)
                        .padding(.top, JGSpacing.xs)
                }
            }
        } else {
            Text("No Selection", comment: "Preview pane without a selected file")
                .jgTextStyle(.body)
                .foregroundStyle(JGColor.textTertiary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// A count in display type and the total size; actions for the selection come in Phase 6.
    private var multiple: some View {
        VStack(alignment: .leading, spacing: JGSpacing.xs) {
            Text(verbatim: "\(preview.selectionCount)")
                .jgTextStyle(.display)
                .foregroundStyle(JGColor.textPrimary)
            Text("Selected", comment: "Preview pane: label under the number of selected files; shown in capitals")
                .jgTextStyle(.label)
                .foregroundStyle(JGColor.textTertiary)
            Text(verbatim: ByteCountFormatter.string(fromByteCount: (pane ?? library).selectedBytes, countStyle: .file))
                .jgTextStyle(.mono)
                .foregroundStyle(JGColor.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .accessibilityElement(children: .combine)
    }
}
