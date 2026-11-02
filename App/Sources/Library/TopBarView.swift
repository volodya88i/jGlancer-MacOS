import JGDesign
import JGModel
import JGSettings
import SwiftUI

/// Breadcrumb · kind chips · sort · thumbnail size (docs/DESIGN.md §8).
struct TopBarView: View {
    let model: LibraryModel
    @Environment(\.appSettings) private var appSettings

    /// The order: video, photo, audio.
    private static let chipOrder: [MediaKind] = [.video, .photo, .audio]

    var body: some View {
        HStack(spacing: JGSpacing.m) {
            // Room for the folder's name: in a narrow bar (a split view's pane) the controls give way first.
            breadcrumb
                .frame(minWidth: JGMetrics.breadcrumbMinWidth, alignment: .leading)
            Spacer(minLength: JGSpacing.m)
            if !model.roots.isEmpty {
                // Outside the variants below, so the field keeps its text, state and focus when they switch.
                SearchBox(model: model)
                    .layoutPriority(2)
                // In a narrow window the size ruler goes first, then the sort menu; nothing is clipped.
                ViewThatFits(in: .horizontal) {
                    controls(sort: true, ruler: true)
                    controls(sort: true, ruler: false)
                    controls(sort: false, ruler: false)
                    controls(sort: false, ruler: false, compactChips: true)
                }
                .layoutPriority(1)
            }
        }
        .padding(.horizontal, JGSpacing.m)
    }

    /// Filters, sort and size; hidden until the library has a folder.
    private func controls(sort: Bool, ruler: Bool, compactChips: Bool = false) -> some View {
        HStack(spacing: JGSpacing.m) {
            chips(compact: compactChips)
            FlagFilterMenu(model: model)
            // An album keeps its own order.
            if sort, model.state.albumID == nil {
                sortMenu
            }
            if ruler {
                JGSlider(
                    value: Binding(get: { model.state.tileSide }, set: { model.setTileSide($0) }),
                    in: JGMetrics.tileSideRange,
                    step: JGMetrics.tileSideStep,
                    accessibilityLabel: String(localized: "Thumbnail Size")
                )
                .frame(width: JGMetrics.sidebarWidth / 2)
            }
        }
        .fixedSize()
    }

    /// Word chips or joined icons (Settings → Appearance → Kind Filters); icons also when the bar is narrow.
    @ViewBuilder
    private func chips(compact: Bool) -> some View {
        if compact || appSettings.kindFilterStyle == .icons {
            JGJoinedToggles(Self.chipOrder.map { kind in
                JGJoinedToggles.Item(
                    id: Self.kindSymbol(kind), symbol: Self.kindSymbol(kind), label: Self.kindName(kind),
                    isOn: model.state.kinds.contains(kind)
                ) { model.toggleKind(kind) }
            })
        } else {
            HStack(spacing: JGSpacing.xxs) {
                ForEach(Self.chipOrder, id: \.self) { kind in
                    Toggle(isOn: Binding(get: { model.state.kinds.contains(kind) }, set: { _ in model.toggleKind(kind) })) {
                        Self.kindName(kind)
                    }
                    .toggleStyle(.jgChip)
                }
            }
        }
    }

    static func kindSymbol(_ kind: MediaKind) -> String {
        switch kind {
        case .photo: "photo.fill"
        case .video: "film.fill"
        case .audio: "waveform"
        }
    }

    @ViewBuilder
    private var breadcrumb: some View {
        if let album = model.currentAlbum {
            HStack(spacing: JGSpacing.xxs) {
                Image(systemName: "rectangle.stack")
                    .font(.system(size: JGTextStyle.body.size))
                    .foregroundStyle(JGColor.textSecondary)
                    .accessibilityHidden(true)
                Text(verbatim: album.name)
                    .jgTextStyle(.body)
                    .foregroundStyle(JGColor.textPrimary)
                    .lineLimit(1)
            }
        } else {
            folderPath
        }
    }

    private var folderPath: some View {
        let path = model.state.folderID.map { model.path(to: $0) } ?? []
        return HStack(spacing: JGSpacing.xxs) {
            ForEach(Array(path.enumerated()), id: \.element.id) { index, folder in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: JGTextStyle.mono.size))
                        .foregroundStyle(JGColor.textTertiary)
                        .accessibilityHidden(true)
                }
                Text(verbatim: folder.name)
                    .jgTextStyle(.body)
                    .foregroundStyle(index == path.count - 1 ? JGColor.textPrimary : JGColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    // The folder shown keeps its name; its parents shorten first.
                    .layoutPriority(index == path.count - 1 ? 1 : 0)
                    .onTapGesture { model.select(folderID: folder.id) }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var sortMenu: some View {
        Menu {
            Picker(selection: Binding(get: { model.state.sort }, set: { model.setSort($0) })) {
                ForEach(AssetQuery.Sort.allCases, id: \.self) { sort in
                    Self.sortName(sort).tag(sort)
                }
            } label: {
                Text("Sort By")
            }
            .pickerStyle(.inline)
            Picker(selection: Binding(get: { model.state.ascending }, set: { model.setAscending($0) })) {
                Text("Ascending").tag(true)
                Text("Descending").tag(false)
            } label: {
                EmptyView()
            }
            .pickerStyle(.inline)
            Divider()
            Toggle(isOn: Binding(get: { model.state.includeSubfolders }, set: { model.setIncludeSubfolders($0) })) {
                Text("Include Subfolders")
            }
        } label: {
            HStack(spacing: JGSpacing.xxs) {
                Self.sortName(model.state.sort)
                Image(systemName: model.state.ascending ? "arrow.up" : "arrow.down")
            }
            .jgTextStyle(.button)
            .foregroundStyle(JGColor.textSecondary)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel(Text("Sort By"))
    }

    static func kindName(_ kind: MediaKind) -> Text {
        switch kind {
        case .photo: Text("Photo", comment: "Media kind")
        case .video: Text("Video", comment: "Media kind")
        case .audio: Text("Audio", comment: "Media kind")
        }
    }

    static func sortName(_ sort: AssetQuery.Sort) -> Text {
        switch sort {
        case .name: Text("Name", comment: "Sort key")
        case .dateModified: Text("Date Modified", comment: "Sort key")
        case .dateCaptured: Text("Date Taken", comment: "Sort key: capture date of photos and videos")
        case .size: Text("Size", comment: "Sort key")
        case .kind: Text("Kind", comment: "Sort key")
        }
    }
}

/// The top bar's star (DECISIONS D-57): show every file, only flagged ones, or one flag. Outline when off, filled
/// in the flag's color when on.
private struct FlagFilterMenu: View {
    let model: LibraryModel

    var body: some View {
        let filter = model.state.flagFilter
        Menu {
            Picker(selection: Binding(get: { filter }, set: { model.setFlagFilter($0) })) {
                Text("All Files", comment: "Flag filter: no filtering").tag(AssetQuery.FlagFilter?.none)
                Text("All Flagged", comment: "Flag filter: files with any flag").tag(AssetQuery.FlagFilter?.some(.flagged))
                ForEach(AssetFlag.menuOrder.filter { $0 != .none }, id: \.self) { flag in
                    Text(verbatim: flag.title).tag(AssetQuery.FlagFilter?.some(.only(flag)))
                }
            } label: {
                Text("Flags", comment: "Settings → Shortcuts group; shown in capitals")
            }
            .pickerStyle(.inline)
        } label: {
            Image(systemName: filter == nil ? "star" : "star.fill")
                .font(.system(size: JGTextStyle.body.size, weight: .semibold))
                .foregroundStyle(color(filter))
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help(Text("Show Flagged Files", comment: "Top bar: flag filter tooltip"))
        .accessibilityLabel(Text("Show Flagged Files", comment: "Top bar: flag filter tooltip"))
    }

    private func color(_ filter: AssetQuery.FlagFilter?) -> JGColorToken {
        switch filter {
        case nil: JGColor.textSecondary
        case .flagged: JGColor.accentText
        case let .only(flag): flag.token
        }
    }
}
