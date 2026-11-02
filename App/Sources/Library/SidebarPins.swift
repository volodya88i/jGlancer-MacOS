import AppKit
import JGDesign
import JGModel
import SwiftUI

/// The PINNED section at the top of the sidebar (D-87), hidden while nothing is pinned: a pin, the folder's name,
/// its path as a tooltip; a click shows the folder. The menu: Unpin, Show in Finder.
struct SidebarPins: View {
    let model: LibraryModel
    /// The pane a click shows the folder in (D-89).
    let target: LibraryModel

    var body: some View {
        let pins = model.pinnedFolders
        if !pins.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                JGSectionHeader(Text("Pinned", comment: "Sidebar section label; shown in capitals"))
                    .padding(.leading, JGSpacing.m)
                    .frame(height: JGMetrics.controlHeightCompact)
                ForEach(pins, id: \.path) { pin in
                    row(pin.folder, path: pin.path)
                }
            }
            .padding(.bottom, JGSpacing.s)
        }
    }

    private func row(_ folder: Folder, path: String) -> some View {
        let isSelected = target.state.folderID == folder.id && target.state.albumID == nil
        return HStack(spacing: JGSpacing.xxs) {
            Image(systemName: "pin")
                .font(.system(size: JGTextStyle.body.size))
                .foregroundStyle(JGColor.textSecondary)
                .frame(width: JGSpacing.m + JGSpacing.xs)
            Text(verbatim: folder.name)
                .jgTextStyle(.body)
                .foregroundStyle(JGColor.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, JGSpacing.xs)
        .frame(height: JGMetrics.controlHeightCompact)
        .background(isSelected ? JGColor.bgRaised : JGColor.bgPanel, in: JGShape(.small))
        .contentShape(JGShape(.small))
        .padding(.horizontal, JGSpacing.xs)
        .help(Text(verbatim: path))
        .onTapGesture { model.showPinned(folder, in: target) }
        .contextMenu {
            Button {
                model.unpin(folder)
            } label: {
                Text("Unpin", comment: "Sidebar: removes a folder from the pinned ones")
            }
            Button {
                model.showInFinder(folder)
            } label: {
                Text("Show in Finder", comment: "Sidebar folder menu")
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
