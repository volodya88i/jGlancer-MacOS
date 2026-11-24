import JGDesign
import JGModel
import JGThumbs
import SwiftUI

/// The sidebar's ALBUMS section (docs/FEATURES.md §6): a row per album with its cover, name and count; + makes a
/// new one. A row takes dropped tiles (they join the album), renames on double-click, and has Rename, Export to
/// Folder… and Delete Album in its menu. Deleting an album never touches files. Compact (the strip, D-128): covers
/// only, under a short line in place of the section's name.
struct SidebarAlbums: View {
    let model: LibraryModel
    /// The pane a click shows the album in (D-89).
    let target: LibraryModel
    var compact = false
    let onExport: (Int64) -> Void
    @State private var albumToDelete: Album?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ZStack(alignment: .leading) {
                JGHairline()
                    .frame(width: JGMetrics.sidebarIconBox)
                    .padding(.leading, SidebarStripGeometry.iconInset)
                    .sidebarStripOpacity(compact)
                header
                    .sidebarLabelOpacity(compact)
                    .allowsHitTesting(!compact)
            }
            .frame(height: JGMetrics.controlHeightCompact)
            ForEach(model.albums) { album in
                AlbumRow(
                    model: model, target: target, album: album, compact: compact, onExport: { onExport(album.id) },
                    onDelete: { albumToDelete = album }
                )
            }
        }
        .confirmationDialog(
            Text("Delete the album “\(albumToDelete?.name ?? "")”?", comment: "Confirmation; the argument is the album name"),
            isPresented: Binding(get: { albumToDelete != nil }, set: {
                if !$0 {
                    albumToDelete = nil
                }
            }),
            presenting: albumToDelete
        ) { album in
            Button(role: .destructive) {
                Task { await model.deleteAlbum(album.id) }
            } label: {
                Text("Delete Album", comment: "Deletes an album; files stay")
            }
        } message: { _ in
            Text("The files stay where they are.", comment: "Delete album confirmation")
        }
    }

    private var header: some View {
        HStack {
            JGSectionHeader(Text("Albums", comment: "Sidebar section label; shown in capitals"))
            Spacer()
            Button(action: newAlbum) {
                Image(systemName: "plus")
                    .font(.system(size: JGTextStyle.body.size))
                    .foregroundStyle(JGColor.textSecondary)
                    .frame(width: JGMetrics.controlHeightCompact, height: JGMetrics.controlHeightCompact)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help(Text("New Album", comment: "Default name of a new album"))
            .accessibilityLabel(Text("New Album", comment: "Default name of a new album"))
        }
        .padding(.leading, JGSpacing.xs)
    }

    private func newAlbum() {
        Task {
            if let id = await model.createAlbum(name: String(localized: "New Album", comment: "Default name of a new album")) {
                model.renamingAlbumID = id
            }
        }
    }
}

/// One album: cover, name (editable in place), count in mono.
private struct AlbumRow: View {
    let model: LibraryModel
    let target: LibraryModel
    let album: Album
    var compact = false
    let onExport: () -> Void
    let onDelete: () -> Void

    @State private var cover: CGImage?
    @State private var isDropTarget = false
    @Environment(\.sidebarRowWidth) private var rowWidth
    @State private var name = ""
    @FocusState private var isEditing: Bool

    private var isSelected: Bool {
        target.state.albumID == album.id
    }

    private var isRenaming: Bool {
        model.renamingAlbumID == album.id
    }

    var body: some View {
        HStack(spacing: 0) {
            coverView
            Spacer(minLength: 0)
        }
        .padding(.leading, compact ? SidebarStripGeometry.iconInset : JGSpacing.xs)
        .frame(width: compact ? SidebarStripGeometry.rowWidth : rowWidth, height: JGMetrics.controlHeightCompact)
        .overlay(alignment: .leading) {
            // The name moves with its row while the sidebar unfolds (D-128).
            label
                .frame(width: max(rowWidth - labelLeading - JGSpacing.xs, 0), alignment: .leading)
                .offset(x: labelLeading)
                .sidebarLabelOpacity(compact)
                .allowsHitTesting(!compact)
        }
        .background(isSelected ? JGColor.bgRaised : JGColor.bgPanel, in: JGShape(.small))
        .jgDropMark(isDropTarget, in: JGShape(.small))
        .contentShape(JGShape(.small))
        .help(compact ? Text(verbatim: album.name) : Text(verbatim: ""))
        // Select on the first click; a count-2 tap gesture before it would hold every click for the double-click
        // interval (~0.5 s). The double click renames alongside.
        .onTapGesture { target.select(albumID: album.id) }
        .simultaneousGesture(TapGesture(count: 2).onEnded {
            if !compact {
                model.renamingAlbumID = album.id
            }
        })
        .contextMenu {
            // The strip has no name to edit in place.
            if !compact {
                Button { model.renamingAlbumID = album.id } label: { Text("Rename", comment: "Undo menu: the operation to undo") }
            }
            Button(action: onExport) { Text("Export to Folder…", comment: "Album menu: copies the album's files to a folder") }
            Divider()
            Button(role: .destructive, action: onDelete) { Text("Delete Album…", comment: "Album menu; files stay") }
        }
        .onDrop(of: [.fileURL], isTargeted: $isDropTarget) { providers in
            Task {
                let ids = await model.assetIDs(for: FolderPicker.urls(from: providers))
                await model.addToAlbum(album.id, assetIDs: ids)
            }
            return true
        }
        .task(id: album.coverAssetID) { await loadCover() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: album.name))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
    }

    private var labelLeading: CGFloat {
        JGSpacing.xs + JGMetrics.sidebarIconBox + JGSpacing.xs
    }

    /// The name (editable in place) and the count.
    private var label: some View {
        HStack(spacing: JGSpacing.xs) {
            if isRenaming {
                TextField(text: $name) { Text("Name", comment: "Rename field") }
                    .textFieldStyle(.plain)
                    .jgTextStyle(.body)
                    .focused($isEditing)
                    .onSubmit(commit)
                    .onExitCommand { model.renamingAlbumID = nil }
                    .onAppear {
                        name = album.name
                        isEditing = true
                    }
                    .onChange(of: isEditing) {
                        if !isEditing {
                            commit()
                        }
                    }
            } else {
                Text(verbatim: album.name)
                    .jgTextStyle(.body)
                    .foregroundStyle(isSelected ? JGColor.textPrimary : JGColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Text(verbatim: "\(album.itemCount)")
                .jgTextStyle(.mono)
                .foregroundStyle(JGColor.textTertiary)
        }
    }

    private var coverView: some View {
        ZStack {
            JGShape(.small).fill(JGColor.bgRaised)
            if let cover {
                Image(decorative: cover, scale: 1)
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: JGTextStyle.mono.size))
                    .foregroundStyle(JGColor.textTertiary)
            }
        }
        .frame(width: JGMetrics.sidebarIconBox, height: JGMetrics.sidebarIconBox)
        .clipShape(JGShape(.small))
        .accessibilityHidden(true)
    }

    private func commit() {
        guard isRenaming else { return }
        model.renamingAlbumID = nil
        let newName = name
        Task { await model.renameAlbum(album.id, to: newName) }
    }

    private func loadCover() async {
        guard let id = album.coverAssetID, let asset = try? await model.store.assets(ids: [id]).first else {
            cover = nil
            return
        }
        let request = ThumbnailRequest(
            assetID: asset.id, url: asset.url, kind: asset.kind, typeIdentifier: asset.typeIdentifier,
            modifiedAt: asset.modifiedAt, duration: asset.duration, bucket: .small
        )
        if let cached = model.thumbnails.cachedThumbnail(for: request) {
            cover = cached
            return
        }
        cover = await model.thumbnails.thumbnail(for: request, priority: .visible)
    }
}
