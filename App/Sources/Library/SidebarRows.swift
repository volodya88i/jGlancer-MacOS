import AppKit
import JGDesign
import SwiftUI

/// One sidebar row: disclosure chevron, folder or disk icon (a library folder's own one, D-129), name, offline mark.
/// Compact (the strip, D-128) the row narrows to a square round its icon and the name fades; the name stays in the
/// row, so it moves with it while the sidebar unfolds.
struct FolderRowView: View {
    let name: String
    let depth: Int
    let icon: FolderIconImage?
    let isRoot: Bool
    var compact = false
    let hasChildren: Bool
    let isExpanded: Bool
    let isSelected: Bool
    let isOffline: Bool
    let isDropTarget: Bool
    let toggle: () -> Void
    @Environment(\.sidebarRowWidth) private var rowWidth

    var body: some View {
        HStack(spacing: 0) {
            disclosure
                .frame(width: compact ? 0 : JGSpacing.m + JGSpacing.xxs, alignment: .leading)
                .clipped()
                .sidebarLabelOpacity(compact)
            FolderIconView(icon: icon, fallback: isRoot ? "externaldrive" : "folder", isSelected: isSelected)
            Spacer(minLength: 0)
        }
        .padding(.leading, compact ? SidebarStripGeometry.iconInset : leading)
        .frame(width: compact ? SidebarStripGeometry.rowWidth : rowWidth, height: JGMetrics.controlHeightCompact)
        .overlay(alignment: .leading) {
            label
                .frame(width: max(rowWidth - labelLeading - JGSpacing.xs, 0), alignment: .leading)
                .offset(x: labelLeading)
                .sidebarLabelOpacity(compact)
                .allowsHitTesting(false)
        }
        .background(isSelected ? JGColor.bgRaised : JGColor.bgPanel, in: JGShape(.small))
        .jgDropMark(isDropTarget, in: JGShape(.small))
        .contentShape(JGShape(.small))
        .help(compact ? Text(verbatim: name) : Text(verbatim: ""))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(Text(verbatim: name))
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : [.isButton])
    }

    private var leading: CGFloat {
        JGSpacing.xs + CGFloat(depth) * JGSpacing.s
    }

    /// After the chevron and the icon.
    private var labelLeading: CGFloat {
        leading + JGSpacing.m + JGSpacing.xxs + JGMetrics.sidebarIconBox + JGSpacing.xxs
    }

    private var label: some View {
        HStack(spacing: JGSpacing.xxs) {
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
        }
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

/// Where the strip puts its icons: centred in its rows (the strip less the rows' side padding).
enum SidebarStripGeometry {
    static let rowWidth = JGMetrics.sidebarStripWidth - 2 * JGSpacing.xs
    static let iconInset = (rowWidth - JGMetrics.sidebarIconBox) / 2
}

extension EnvironmentValues {
    /// A sidebar row's width when unfolded (the panel's content is laid out at it also while folded, D-128).
    @Entry var sidebarRowWidth: CGFloat = JGMetrics.sidebarWidth - 2 * JGSpacing.xs
}

extension View {
    /// Names and section titles: they fade out quickly when the sidebar folds and in a moment after it starts to
    /// unfold, so they never crowd the moving icons.
    func sidebarLabelOpacity(_ compact: Bool) -> some View {
        opacity(compact ? 0 : 1)
            .animation(
                compact ? .easeOut(duration: JGMetrics.fadeDuration / 2) : .easeIn(duration: JGMetrics.fadeDuration)
                    .delay(JGMetrics.fadeDuration / 3),
                value: compact
            )
    }

    /// What only the strip shows: the opposite timing.
    func sidebarStripOpacity(_ compact: Bool) -> some View {
        opacity(compact ? 1 : 0)
            .animation(
                compact ? .easeIn(duration: JGMetrics.fadeDuration)
                    .delay(JGMetrics.fadeDuration / 3) : .easeOut(duration: JGMetrics.fadeDuration / 2),
                value: compact
            )
            .allowsHitTesting(compact)
    }
}

/// The Trash at the bottom of the sidebar: drop tiles (or files from Finder) on it to move them to the Trash
/// (undoable); a click shows the Trash in Finder. Compact: the icon alone.
struct TrashRow: View {
    let model: LibraryModel
    var compact = false
    @State private var isTargeted = false
    @Environment(\.sidebarRowWidth) private var rowWidth

    var body: some View {
        Button {
            NSWorkspace.shared.open(URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".Trash", isDirectory: true))
        } label: {
            HStack(spacing: 0) {
                Image(systemName: isTargeted ? "trash.fill" : "trash")
                    .font(.system(size: JGTextStyle.body.size))
                    .foregroundStyle(isTargeted ? JGColor.textPrimary : JGColor.textSecondary)
                    .frame(width: JGMetrics.sidebarIconBox)
                Spacer(minLength: 0)
            }
            .padding(.leading, compact ? SidebarStripGeometry.iconInset : JGSpacing.xs)
            .frame(width: compact ? SidebarStripGeometry.rowWidth : rowWidth, height: JGMetrics.controlHeightCompact)
            .overlay(alignment: .leading) {
                Text("Trash", comment: "Sidebar: the system Trash")
                    .jgTextStyle(.body)
                    .foregroundStyle(isTargeted ? JGColor.textPrimary : JGColor.textSecondary)
                    .fixedSize()
                    .offset(x: JGSpacing.xs + JGMetrics.sidebarIconBox + JGSpacing.xxs)
                    .sidebarLabelOpacity(compact)
            }
            .background(isTargeted ? JGColor.bgRaised : JGColor.bgPanel, in: JGShape(.small))
            .overlay {
                if isTargeted {
                    JGShape(.small).strokeBorder(JGColor.danger, lineWidth: JGMetrics.selectionEdgeWidth)
                }
            }
            .contentShape(JGShape(.small))
        }
        .buttonStyle(.plain)
        .padding(.horizontal, JGSpacing.xs)
        .frame(maxWidth: .infinity, alignment: .leading)
        .help(Text("Show the Trash in Finder; drop files here to move them to the Trash", comment: "Sidebar Trash tooltip"))
        .accessibilityLabel(Text("Trash", comment: "Sidebar: the system Trash"))
        .onDrop(of: [.fileURL], isTargeted: $isTargeted) { providers in
            Task {
                let urls = await FolderPicker.urls(from: providers)
                model.onTrashFiles?(urls)
            }
            return true
        }
    }
}
