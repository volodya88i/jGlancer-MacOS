import JGDesign
import JGModel
import SwiftUI

/// The size map as a side module (D-127): the main pane's folder as nested rectangles by size; its header says what is
/// under the pointer, or the folder and its total.
struct SizeMapModule: View {
    let model: SizeMapModel
    let library: LibraryModel
    let slot: ModuleSlot

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: JGSpacing.xs) {
                JGSectionHeader(Text("Size Map", comment: "Section label of the size map; shown in capitals"))
                Text(verbatim: info)
                    .jgTextStyle(.mono)
                    .foregroundStyle(JGColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer(minLength: JGSpacing.xs)
                ModuleHeaderButtons(module: .sizeMap, slot: slot, library: library)
            }
            .padding(.horizontal, JGSpacing.m)
            .frame(height: JGMetrics.barHeight)
            content
                .padding([.horizontal, .bottom], JGSpacing.xs)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(JGColor.bgPanel)
        .task(id: SizeMapModel.key(for: library)) {
            model.reload(for: library)
        }
    }

    @ViewBuilder
    private var content: some View {
        switch model.content {
        case .tree, .loading:
            SizeMapCanvas(
                tree: model.tree, treeVersion: model.treeVersion, selected: library.selection.selected,
                onHover: { model.hovered = $0 },
                onClick: { item in
                    if case let .file(id) = item {
                        library.reveal(id)
                    }
                },
                onDoubleClick: { item in
                    switch item {
                    case let .file(id): library.open(id)
                    case let .folder(id): library.select(folderID: id)
                    }
                }
            )
        case .album:
            message(Text("Albums have no size map: choose a folder.", comment: "Size map while an album is shown"))
        case .empty:
            message(Text("Nothing here.", comment: "Size map of a folder without files of the kinds shown"))
        }
    }

    private func message(_ text: Text) -> some View {
        text
            .jgTextStyle(.body)
            .foregroundStyle(JGColor.textTertiary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// The node under the pointer, else the folder shown: its name and size.
    private var info: String {
        guard let node = model.hovered ?? model.tree.root else { return "" }
        return node.name + " · " + ByteCountFormatter.string(fromByteCount: node.size, countStyle: .file)
    }
}

/// A side module's header buttons (D-127): move to the other place (swapping with the module there), and close.
struct ModuleHeaderButtons: View {
    let module: LibraryModule
    let slot: ModuleSlot
    let library: LibraryModel

    var body: some View {
        HStack(spacing: 0) {
            button(
                symbol: slot == .right ? "rectangle.bottomthird.inset.filled" : "rectangle.righthalf.inset.filled",
                label: slot == .right
                    ? Text("Move Down", comment: "Side module header: puts the module under the files")
                    : Text("Move to the Right", comment: "Side module header: puts the module right of the files")
            ) {
                library.moveModule(module)
            }
            button(symbol: "xmark", label: closeLabel) {
                library.setModuleVisible(module, false)
            }
        }
    }

    private var closeLabel: Text {
        switch module {
        case .preview: Text("Hide Preview (⌥⌘0)", comment: "Preview pane: close button tooltip")
        case .sizeMap: Text("Hide Size Map (⌥⌘T)", comment: "Size map: close button tooltip")
        }
    }

    private func button(symbol: String, label: Text, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: JGTextStyle.mono.size, weight: .semibold))
                .foregroundStyle(JGColor.textSecondary)
                .frame(width: JGMetrics.controlHeightCompact, height: JGMetrics.controlHeightCompact)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(label)
        .accessibilityLabel(label)
    }
}
