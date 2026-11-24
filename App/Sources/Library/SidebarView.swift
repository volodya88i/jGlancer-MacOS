import AppKit
import JGDesign
import JGModel
import SwiftUI

/// Library folders as a tree (docs/FEATURES.md §1). Custom rows keep the design's look; ↑/↓ move,
/// ←/→ collapse and expand, like an outline view. Compact, it is the folded sidebar's strip (D-128): the library folders,
/// the albums and the Trash as icons in the same rows, so unfolding moves the icons to their places and brings the
/// names in.
struct SidebarView: View {
    /// The main pane: roots, trees, albums, pins and changes.
    let model: LibraryModel
    /// The pane a click shows a folder or album in: the active one of a split view (D-89).
    var target: LibraryModel?
    /// The fold button in the top row (D-128): Hide on the docked sidebar, Keep Open on the one over the files.
    var toggleRole = SidebarToggleButton.Role.hide
    /// The strip: icons only, no subfolders, pins or section names.
    var compact = false
    @State private var rootToRemove: RootFolder?
    /// The library folder whose icon is being chosen (D-129).
    @State private var iconRoot: RootFolder?
    /// The folder row under a drag of files.
    @State private var dropTarget: Int64?
    @FocusState private var isFocused: Bool
    @Environment(\.sidebarRowWidth) private var rowWidth

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
            topRow
            if !compact {
                SidebarPins(model: model, target: pane)
                    .transition(.opacity)
            }
            foldersHeader
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(rows) { row in
                        rowView(row)
                            .transition(.opacity)
                    }
                    SidebarAlbums(model: model, target: pane, compact: compact) { albumID in
                        model.onExportAlbum?(albumID)
                    }
                    .padding(.top, JGSpacing.m)
                }
                .padding(.horizontal, JGSpacing.xs)
                .padding(.bottom, JGSpacing.m)
            }
            .scrollIndicators(compact ? .never : .automatic)
            // As wide as what shows: the panel's content is laid out at the unfolded width (D-128), and a scroll view
            // left that wide on the strip would take the pointer over the files beside it.
            .frame(width: compact ? JGMetrics.sidebarStripWidth : rowWidth + 2 * JGSpacing.xs, alignment: .leading)
            .focusable()
            .focused($isFocused)
            .focusEffectDisabled()
            .onMoveCommand(perform: moveSelection)
            JGHairline()
            TrashRow(model: model, compact: compact)
                .frame(height: JGMetrics.statusBarHeight)
        }
        .background(JGColor.bgPanel)
        .sheet(item: $iconRoot) { root in
            FolderIconPicker(model: model, root: root)
        }
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
            if !compact, model.expandedFolders.contains(node.id) {
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
            icon: row.root.flatMap { model.rootIcons[$0.id] },
            isRoot: row.root != nil,
            compact: compact,
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
        if let root = row.root {
            Button {
                iconRoot = root
            } label: {
                Text("Folder Icon…", comment: "Sidebar menu of a library folder: choose its symbol, emoji or picture")
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
                model.hide(row.node.folder)
            } label: {
                Text("Hide from Library", comment: "Sidebar folder menu: the subfolder leaves the library's views; files stay")
            }
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

// MARK: The top rows

extension SidebarView {
    /// The window's buttons sit here, level with the top bar, with the fold button at the end of the row. On the strip
    /// the row looks like the top bar running on (its glass and its hairline).
    private var topRow: some View {
        VStack(spacing: 0) {
            Color.clear.frame(height: JGMetrics.barHeight)
            JGHairline().opacity(compact ? 1 : 0)
        }
        .background {
            ZStack {
                Rectangle().fill(JGColor.bgBase)
                Color.clear.jgBarBackground(JGColor.bgBase)
            }
            .opacity(compact ? 1 : 0)
        }
        .contentShape(Rectangle())
        .titleBarDoubleClick()
        .overlay(alignment: .topTrailing) {
            SidebarToggleButton(role: toggleRole) { model.setSidebarCollapsed(toggleRole == .hide) }
                .frame(height: JGMetrics.barHeight)
                .padding(.trailing, JGSpacing.xs)
                .sidebarLabelOpacity(compact)
                .allowsHitTesting(!compact)
        }
    }

    /// FOLDERS and its +; on the strip the Show Sidebar button stands in the same row.
    private var foldersHeader: some View {
        ZStack(alignment: .leading) {
            SidebarToggleButton(role: .show) { model.setSidebarCollapsed(false) }
                .frame(width: JGMetrics.sidebarStripWidth)
                .sidebarStripOpacity(compact)
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
            .sidebarLabelOpacity(compact)
            .allowsHitTesting(!compact)
        }
        .frame(height: JGMetrics.controlHeightCompact)
    }
}
