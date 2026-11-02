import JGActions
import JGDesign
import SwiftUI

/// Rename… with several files (docs/FEATURES.md §7): a template of text and tokens (name, number, date), the first
/// number and its digits, and the list of old and new names with any problem marked. Rename runs as one undoable
/// batch; extensions are kept unless a new one is given for all (D-75).
struct BatchRenameSheet: View {
    let fileOps: FileOperationsModel
    let files: [BatchRenamePattern.File]

    @State private var pattern = BatchRenamePattern(template: BatchRenamePattern.nameToken)
    @FocusState private var isFocused: Bool
    @Environment(\.dismiss) private var dismiss

    /// Folder listings for the "taken" check, read once.
    @State private var listings: [URL: Set<String>] = [:]

    var body: some View {
        let names = pattern.names(for: files)
        let problems = BatchRenamePattern.problems(files: files, names: names) { listings[$0] ?? [] }
        VStack(alignment: .leading, spacing: JGSpacing.m) {
            Text("Rename \(files.count) Files", comment: "Batch rename: title; the argument is the number of files")
                .jgTextStyle(.heading)
                .foregroundStyle(JGColor.textPrimary)
            templateRow
            numberRow
            extensionRow
            preview(names: names, problems: problems)
            buttons(
                enabled: problems.allSatisfy { $0 == nil } && zip(files, names).contains { $0.url.lastPathComponent != $1 },
                names: names
            )
        }
        .padding(JGSpacing.l)
        .frame(width: JGMetrics.batchRenameWidth)
        .background(JGColor.bgPanel)
        .onAppear {
            isFocused = true
            listings = Dictionary(grouping: files.map { $0.url.deletingLastPathComponent() }) { $0 }.mapValues { folders in
                let path = folders[0].path
                return Set((try? FileManager.default.contentsOfDirectory(atPath: path)) ?? [])
            }
        }
    }

    private var templateRow: some View {
        VStack(alignment: .leading, spacing: JGSpacing.xs) {
            TextField(text: $pattern.template) {
                Text("Template", comment: "Batch rename: the name pattern field")
            }
            .textFieldStyle(.roundedBorder)
            .focused($isFocused)
            HStack(spacing: JGSpacing.xs) {
                token(Text("Name", comment: "Batch rename token: the old name"), BatchRenamePattern.nameToken)
                token(Text("Number", comment: "Batch rename token: a counter"), BatchRenamePattern.counterToken)
                token(Text("Date", comment: "Batch rename token: capture or modification date"), BatchRenamePattern.dateToken)
            }
        }
    }

    private func token(_ title: Text, _ token: String) -> some View {
        Button { pattern.template += token } label: {
            title
        }
        .buttonStyle(.jg(.secondary))
        .help(Text(verbatim: token))
    }

    private var numberRow: some View {
        HStack(spacing: JGSpacing.m) {
            Stepper(value: $pattern.start, in: 0 ... 999_999) {
                Text("Start at \(pattern.start)", comment: "Batch rename: the first number")
                    .jgTextStyle(.body)
                    .foregroundStyle(JGColor.textSecondary)
            }
            Picker(selection: $pattern.digits) {
                Text("Digits: auto", comment: "Batch rename: counter digits chosen automatically").tag(0)
                ForEach(2 ... 5, id: \.self) { digits in
                    Text("Digits: \(digits)", comment: "Batch rename: counter digits").tag(digits)
                }
            } label: {
                EmptyView()
            }
            .fixedSize()
        }
    }

    /// One extension for every file, names unchanged by the default template.
    private var extensionRow: some View {
        VStack(alignment: .leading, spacing: JGSpacing.xxs) {
            TextField(text: $pattern.newExtension) {
                Text("New extension (empty keeps each file's own)", comment: "Batch rename: field for one extension for all files")
            }
            .textFieldStyle(.roundedBorder)
            if !pattern.newExtension.trimmingCharacters(in: CharacterSet(charactersIn: ". ")).isEmpty {
                Text("Only the name changes: the file is not converted.", comment: "Batch rename: note under the extension field")
                    .jgTextStyle(.body)
                    .foregroundStyle(JGColor.textTertiary)
            }
        }
    }

    private func preview(names: [String], problems: [BatchRenamePattern.Problem?]) -> some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: JGSpacing.xxs) {
                ForEach(Array(files.enumerated()), id: \.offset) { index, file in
                    HStack(spacing: JGSpacing.xs) {
                        Text(verbatim: file.url.lastPathComponent)
                            .foregroundStyle(JGColor.textSecondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Image(systemName: "arrow.right")
                            .foregroundStyle(JGColor.textTertiary)
                            .accessibilityHidden(true)
                        Text(verbatim: problems[index].map(Self.message) ?? names[index])
                            .foregroundStyle(problems[index] == nil ? JGColor.textPrimary : JGColor.danger)
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .jgTextStyle(.mono)
                }
            }
        }
        .frame(height: JGMetrics.batchRenameListHeight)
        .padding(JGSpacing.xs)
        .background(JGColor.bgBase, in: JGShape(.small))
    }

    private func buttons(enabled: Bool, names: [String]) -> some View {
        HStack {
            Spacer()
            Button { dismiss() } label: { Text("Cancel") }
                .buttonStyle(.jg(.secondary))
                .keyboardShortcut(.cancelAction)
            Button {
                fileOps.renameAll(zip(files, names).filter { $0.url.lastPathComponent != $1 }.map { ($0.url, $1) })
                dismiss()
            } label: {
                Text(LocalizedStringResource("rename.button", defaultValue: "Rename", comment: "Button: renames the file or files"))
            }
            .buttonStyle(.jg(.primary))
            .keyboardShortcut(.defaultAction)
            .disabled(!enabled)
        }
    }

    static func message(_ problem: BatchRenamePattern.Problem) -> String {
        switch problem {
        case .empty: String(localized: "No name", comment: "Batch rename problem: the name is empty")
        case .invalidCharacters: String(localized: "Can't use / : or a leading dot", comment: "Batch rename problem")
        case .duplicate: String(localized: "Same name twice", comment: "Batch rename problem: two files would get one name")
        case .taken: String(localized: "Name taken", comment: "Batch rename problem: another file has this name")
        }
    }
}
