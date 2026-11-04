import AppKit
import JGDesign
import JGScanner
import SwiftUI

/// While folders added in this session are scanned for the first time (D-85, W-70): a card at the bottom of the
/// window with each folder's name, the files and folders found so far, a running bar, and Stop, which removes the
/// folder from the library again (files on disk are never touched).
struct AddingFoldersCard: View {
    let model: LibraryModel

    var body: some View {
        let adding = model.roots.filter { model.indexer.adding[$0.id] != nil }
        if !adding.isEmpty {
            VStack(alignment: .leading, spacing: JGSpacing.s) {
                ForEach(adding) { root in
                    row(root.url.lastPathComponent, found: model.indexer.adding[root.id] ?? ScanProgress()) {
                        Task { await model.removeRoot(root.id) }
                    }
                }
            }
            .padding(JGSpacing.m)
            .frame(width: JGMetrics.addingCardWidth)
            .jgPanelBackground(JGColor.bgRaised, in: JGShape(.medium))
            .overlay(JGShape(.medium).strokeBorder(JGColor.lineHair, lineWidth: JGMetrics.outlineWidth))
            .shadow(color: .black.opacity(JGMetrics.toastShadowOpacity), radius: JGMetrics.toastShadowRadius)
            .padding(.bottom, JGSpacing.xl)
        }
    }

    private func row(_ name: String, found: ScanProgress, stop: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: JGSpacing.xs) {
            HStack {
                Text("Adding “\(name)”", comment: "Card while a folder is added; the argument is the folder's name")
                    .jgTextStyle(.body)
                    .foregroundStyle(JGColor.textPrimary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Button(action: stop) {
                    Text("Stop", comment: "Toast: stops a running file operation")
                }
                .buttonStyle(.jg(.secondary))
                .help(Text("Stop adding and remove the folder from the library", comment: "Adding card: Stop button help"))
            }
            Text("\(found.files) files in \(found.folders) folders", comment: "Adding card: what the scan found so far")
                .jgTextStyle(.mono)
                .foregroundStyle(JGColor.textSecondary)
                .monospacedDigit()
            ProgressView()
                .progressViewStyle(.linear)
                .tint(JGColor.accent)
        }
        .accessibilityElement(children: .combine)
    }
}

extension LibraryModel {
    /// "Add the whole drive …?" before a volume joins the library.
    static func confirmWholeDrive(_ url: URL) -> Bool {
        let alert = NSAlert()
        let name = FileManager.default.displayName(atPath: url.path)
        alert.messageText = String(localized: "Add the whole drive “\(name)”?", comment: "Alert before adding a whole volume")
        alert.informativeText = String(
            localized: "Every photo, video and audio file on it will be indexed. This can take a while.",
            comment: "Alert before adding a whole volume: explanation"
        )
        alert.addButton(withTitle: String(localized: "Add Drive", comment: "Alert button: add the whole volume"))
        alert.addButton(withTitle: String(localized: "Cancel", comment: "Alert button"))
        return alert.runModal() == .alertFirstButtonReturn
    }
}
