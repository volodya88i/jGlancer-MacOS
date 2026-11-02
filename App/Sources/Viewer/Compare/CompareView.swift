import AppKit
import JGDesign
import SwiftUI

/// Compare filling the window (W-77): the top bar (‹ Library, link, swap, fit, 100 %, Get Info of both) over the two
/// photos side by side with a hairline between them, each with its name and "w × h · size" bottom-left.
struct CompareView: View {
    let model: CompareModel
    let onClose: () -> Void
    let onInfo: () -> Void
    let contextMenu: (Int) -> NSMenu?

    var body: some View {
        VStack(spacing: 0) {
            ViewerTopBar(
                name: String(localized: "Compare", comment: "Action: two photos side by side"), index: 0, count: 0,
                onClose: onClose
            ) {
                ViewerIconButton(
                    symbol: model.isLinked ? "link" : "personalhotspot.slash",
                    label: Text("Link Zoom (L)", comment: "Compare: both photos zoom and pan together"),
                    isOn: model.isLinked
                ) { model.apply(.toggleLink) }
                ViewerIconButton(symbol: "arrow.left.arrow.right", label: Text("Swap (X)", comment: "Compare: the photos change places")) {
                    model.apply(.swap)
                }
                ViewerIconButton(symbol: "arrow.down.right.and.arrow.up.left", label: Text("Fit", comment: "Zoom to fit the window")) {
                    model.apply(.fit)
                }
                ViewerIconButton(symbol: "1.magnifyingglass", label: Text("Actual Size", comment: "Zoom to 100 %")) {
                    model.apply(.actualSize)
                }
                ViewerIconButton(symbol: "info.circle", label: Text("Get Info", comment: "Action"), action: onInfo)
            }
            HStack(spacing: 0) {
                side(0)
                JGHairline(.vertical)
                side(1)
            }
        }
        .background(JGColor.bgMedia)
        .ignoresSafeArea()
    }

    private func side(_ index: Int) -> some View {
        ZStack(alignment: .bottomLeading) {
            if model.sides.indices.contains(index) {
                CompareCanvas(model: model, side: index, contextMenu: contextMenu)
                caption(model.sides[index])
                    .padding(JGSpacing.s)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func caption(_ side: CompareModel.Side) -> some View {
        VStack(alignment: .leading, spacing: JGSpacing.xxs) {
            Text(verbatim: side.asset.name)
                .jgTextStyle(.body)
                .foregroundStyle(JGColor.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            Text(verbatim: details(side))
                .jgTextStyle(.mono)
                .foregroundStyle(JGColor.textSecondary)
        }
        .padding(.horizontal, JGSpacing.s)
        .padding(.vertical, JGSpacing.xs)
        .background(JGColor.overlayScrim, in: JGShape(.medium))
    }

    private func details(_ side: CompareModel.Side) -> String {
        let bytes = ByteCountFormatter.string(fromByteCount: side.asset.size, countStyle: .file)
        guard side.pixelSize.width > 0 else { return bytes }
        return "\(Int(side.pixelSize.width)) × \(Int(side.pixelSize.height)) · \(bytes)"
    }
}
