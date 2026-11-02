import AppKit
import JGDesign
import JGModel
import SwiftUI

/// Library folders as a tree (docs/FEATURES.md §1). Custom rows keep the design's look; ↑/↓ move,
/// ←/→ collapse and expand, like an outline view.
struct SidebarView: View {
    /// The main pane: roots, trees, albums, pins and changes.
    let model: LibraryModel
    /// The pane a click shows a folder or album in: the active one of a split view (D-89).
    var target: LibraryModel?
    @State private var rootToRemove: RootFolder?
    /// The folder row under a drag of files.
    @State private var dropTarget: Int64?
    @FocusState private var isFocused: Bool

    private var pane: LibraryModel {
        target ?? model
    }

    private struct Row: Identifiable {
        let node: FolderNode
        let depth: Int
        let root: RootFolder?
        var id: Int64 {
            node.id
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // The window controls sit here, level with the top bar.
            Color.clear.frame(height: JGMetrics.barHeight)
            SidebarPins(model: model, target: pane)
            HStack {
                JGSectionHeader(Text("Folders", comment: "Sidebar section label; shown in capitals"))
                Spacer()
                Button {
                    Task { await model.addFolders(FolderPicker.chooseFolders()) }
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: JGTextStyle.body.size))
                        .foregroundStyle(JGColor.textSecondary)
                        .frame(width: JGMetrics.controlHeightCompact, height: JGMetrics.controlHeightCompact)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Text("Add Folder…"))
                .accessibilityLabel(Text("Add Folder…"))
            }
            .padding(.leading, JGSpacing.m)
            .padding(.trailing, JGSpacing.xs)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        rowView(row)
                    }
                    SidebarAlbums(model: model, target: pane) { albumID in
                        model.onExportAlbum?(albumID)
                    }
                    .padding(.top, JGSpacing.m)
                }
                .padding(.horizontal, JGSpacing.xs)
                .padding(.bottom, JGSpacing.m)
            }
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onMoveCommand(perform: moveSelection)
            JGHairline()
            TrashRow(model: model)
                .padding(JGSpacing.xs)
        }
        .background(JGColor.bgPanel)
        .confirmationDialog(
            removalTitle,
            isPresented: Binding(get: { rootToRemove != nil }, set: {
                if !$0 {
                    rootToRemove = nil
                }
            }),
            presenting: rootToRemove
        ) { root in
            Button(role: .destructive) {
                Task { await model.removeRoot(root.id) }
            } label: {
                Text("Remove", comment: "Confirms removing a folder from the library")
            }
            Button(role: .cancel) {} label: {
                Text("Cancel")
            }
        } message: { _ in
            Text("Files stay on disk.", comment: "Explains that removing a library folder keeps the files")
        }
    }

    private var removalTitle: Text {
        let name = rootToRemove.map { URL(fileURLWithPath: $0.path).lastPathComponent } ?? ""
        return Text("Remove “\(name)” from the library?", comment: "Confirmation title; the argument is a folder name")
    }

    private var rows: [Row] {
        var rows: [Row] = []
        func visit(_ node: FolderNode, depth: Int, root: RootFolder?) {
            rows.append(Row(node: node, depth: depth, root: root))
            if model.expandedFolders.contains(node.id) {
                for child in node.children ?? [] {
                    visit(child, depth: depth + 1, root: nil)
                }
            }
        }
        // A folder being added shows up once its first scan is done (D-85).
        for root in model.roots where model.indexer.adding[root.id] == nil {
            if let tree = model.trees[root.id] {
                visit(tree, depth: 0, root: root)
            }
        }
        return rows
    }

    private func rowView(_ row: Row) -> some View {
        FolderRowView(
            name: row.node.folder.name,
            depth: row.depth,
            isRoot: row.root != nil,
            hasChildren: row.node.children != nil,
            isExpanded: model.expandedFolders.contains(row.id),
            isSelected: pane.state.folderID == row.id && pane.state.albumID == nil,
            isOffline: row.root.map { model.offlineRoots.contains($0.id) } ?? false,
            isDropTarget: dropTarget == row.id,
            toggle: { toggle(row.id) }
        )
        .onDrop(of: [.fileURL], isTargeted: Binding(
            get: { dropTarget == row.id },
            set: { targeted in
                if targeted {
                    dropTarget = row.id
                } else if dropTarget == row.id {
                    dropTarget = nil
                }
            }
        )) { providers in
            guard let folder = model.url(of: row.node.folder) else { return false }
            let copying = NSEvent.modifierFlags.contains(.option)
            Task {
                let urls = await FolderPicker.urls(from: providers)
                    .filter { $0.deletingLastPathComponent().standardizedFileURL != folder.standardizedFileURL }
                model.onDropFiles?(urls, folder, copying)
            }
            return true
        }
        .onDrag { PaneFolderDrag.provider(for: row.id) }
        .onTapGesture {
            pane.select(folderID: row.id)
            isFocused = true
        }
        .contextMenu { folderMenu(row) }
    }

    /// New Folder…, Show in Finder, then Remove from Library (a root) or Move to Trash (D-86).
    @ViewBuilder
    private func folderMenu(_ row: Row) -> some View {
        Button {
            model.newFolder(in: row.node.folder)
        } label: {
            Text("New Folder…", comment: "Sidebar folder menu: makes a folder inside")
        }
        Button {
            model.showInFinder(row.node.folder)
        } label: {
            Text("Show in Finder", comment: "Sidebar folder menu")
        }
        if model.isPinned(row.node.folder) {
            Button {
                model.unpin(row.node.folder)
            } label: {
                Text("Unpin", comment: "Sidebar: removes a folder from the pinned ones")
            }
        } else {
            Button {
                model.pin(row.node.folder)
            } label: {
                Text("Pin to Sidebar", comment: "Sidebar folder menu: adds the folder to the pinned ones")
            }
        }
        Divider()
        if let root = row.root {
            Button {
                rootToRemove = root
            } label: {
                Text("Remove from Library", comment: "Context menu item; files are not touched")
            }
        } else {
            Button {
                model.trash(row.node.folder)
            } label: {
                Text("Move to Trash", comment: "Action")
            }
        }
    }

    private func toggle(_ id: Int64) {
        if model.expandedFolders.contains(id) {
            model.expandedFolders.remove(id)
        } else {
            model.expandedFolders.insert(id)
        }
    }

    private func moveSelection(_ direction: MoveCommandDirection) {
        let rows = rows
        guard let current = rows.firstIndex(where: { $0.id == pane.state.folderID }) else {
            if let first = rows.first {
                pane.select(folderID: first.id)
            }
            return
        }
        switch direction {
        case .up where current > 0:
            pane.select(folderID: rows[current - 1].id)
        case .down where current < rows.count - 1:
            pane.select(folderID: rows[current + 1].id)
        case .left:
            model.expandedFolders.remove(rows[current].id)
        case .right where rows[current].node.children != nil:
            model.expandedFolders.insert(rows[current].id)
        default:
            break
        }
    }
}

/// One sidebar row: disclosure chevron, folder or disk icon, name, offline mark.
private struct FolderRowView: View {
    let name: String
    let depth: Int
    let isRoot: Bool
    let hasChildren: Bool
    let isExpanded: Bool
    let isSelected: Bool
    let isOffline: Bool
    let isDropTarget: Bool
    let toggle: () -> Void

    var body: some View {
        HStack(spacing: JGSpacing.xxs) {
            disclosure
            Image(systemName: isRoot ? "externaldrive" : "folder")
                .font(.system(size: JGTextStyle.body.size))
                .foregroundStyle(isSelected ? JGColor.textPrimary : JGColor.textSecondary)
            Text(verbatim: name)
                .jgTextStyle(.body)
                .foregroundStyle(isOffline ? JGColor.textTertiary : (isSelected ? JGColor.textPrimary : JGColor.textSecondary))
                .lineLimit(1)
                .truncationMode(.middle)
            if isOffline {
                Text("Offline", comment: "A library folder whose disk is not available")
                    .jgTextStyle(.label)
                    .foregroundStyle(JGColor.textTertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.leading, CGFloat(depth) * JGSpacing.s)
        .padding(.horizontal, JGSpacing.xs)
        .frame(height: JGMetrics.controlHeightCompact)
        .background(isSelected ? JGColor.bgRaised : JGColor.bgPanel, in: JGShape(.small))
        .overlay {
            if isDropTarget {
                JGShape(.small).strokeBorder(JGColor.accent, lineWidth: JGMetrics.selectionEdgeWidth)
            }
        }
        .contentShape(JGShape(.small))
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
    }

    private var disclosure: some View {
        Group {
            if hasChildren {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .onTapGesture(perform: toggle)
                    .accessibilityLabel(isExpanded ? Text("Collapse") : Text("Expand"))
            } else {
                Color.clear
            }
        }
        .font(.system(size: JGTextStyle.mono.size, weight: .semibold))
        .foregroundStyle(JGColor.textTertiary)
        .frame(width: JGSpacing.m)
    }
}

/// The Trash at the bottom of the sidebar: drop tiles (or files from Finder) on it to move them to the Trash
/// (undoable); a click shows the Trash in Finder.
private struct TrashRow: View {
    let model: LibraryModel
    @State private var isTargeted = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash", isDirectory: true))
        } label: {
            HStack(spacing: JGSpacing.xxs) {
                Image(systemName: isTargeted ? "trash.fill" : "trash")
                    .font(.system(size: JGTextStyle.body.size))
                    .foregroundStyle(isTargeted ? JGColor.textPrimary : JGColor.textSecondary)
                    .frame(width: JGSpacing.m + JGSpacing.xs)
                Text("Trash", comment: "Sidebar: the system Trash")
                    .jgTextStyle(.body)
                    .foregroundStyle(isTargeted ? JGColor.textPrimary : JGColor.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, JGSpacing.xs)
            .frame(height: JGMetrics.controlHeightCompact)
            .background(isTargeted ? JGColor.bgRaised : JGColor.bgPanel, in: JGShape(.small))
            .overlay {
                if isTargeted {
                    JGShape(.small).strokeBorder(JGColor.danger, lineWidth: JGMetrics.selectionEdgeWidth)
                }
            }
            .contentShape(JGShape(.small))
        }
        .buttonStyle(.plain)
        .help(Text("Show the Trash in Finder; drop files here to move them to the Trash", comment: "Sidebar Trash tooltip"))
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            Task {
                let urls = await FolderPicker.urls(from: providers)
                model.onTrashFiles?(urls)
            }
            return true
        }
    }
}
