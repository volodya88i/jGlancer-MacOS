import JGDesign
import SwiftUI

/// Rename (docs/FEATURES.md §7): one field with the current name, the part before the extension selected;
/// Return renames, Esc cancels; a taken or invalid name is explained in one line and the sheet stays.
struct RenameSheet: View {
    let fileOps: FileOperationsModel
    let url: URL

    @State private var name: String
    @State private var error: String?
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    init(fileOps: FileOperationsModel, url: URL) {
        self.fileOps = fileOps
        self.url = url
        _name = State(initialValue: url.lastPathComponent)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: JGSpacing.s) {
            Text("Rename", comment: "Undo menu: the operation to undo")
                .jgTextStyle(.heading)
                .foregroundStyle(JGColor.textPrimary)
            TextField(text: $name) {
                Text("Name", comment: "Rename field")
            }
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            .onSubmit(rename)
            if let error {
                Text(verbatim: error)
                    .jgTextStyle(.body)
                    .foregroundStyle(JGColor.danger)
            }
            HStack {
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                }
                .buttonStyle(.jg(.secondary))
                .keyboardShortcut(.cancelAction)
                Button(action: rename) {
                    Text(LocalizedStringResource("rename.button", defaultValue: "Rename", comment: "Button: renames the file or files"))
                }
                .buttonStyle(.jg(.primary))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(JGSpacing.l)
        .frame(width: JGMetrics.previewPaneMaxWidth)
        .background(JGColor.bgPanel)
        .onAppear { isFocused = true }
    }

    private func rename() {
        Task {
            if let message = await fileOps.rename(url, to: name) {
                error = message
            } else {
                dismiss()
            }
        }
    }
}
