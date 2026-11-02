import JGDesign
import SwiftUI

/// Counts and sizes in mono, background activity, the latest problem (docs/DESIGN.md §8).
struct StatusBarView: View {
    let model: LibraryModel

    var body: some View {
        HStack(spacing: JGSpacing.s) {
            Group {
                let count = model.allRefs.count // files, with the frames of folded sequences (D-84)
                let selected = model.selection.selected.count
                if selected > 0 {
                    Text("\(selected) of \(count) selected", comment: "Status bar; first number selected, second shown")
                    Text(verbatim: "·").foregroundStyle(JGColor.textTertiary)
                    Text(verbatim: ByteCountFormatter.string(fromByteCount: model.selectedBytes, countStyle: .file))
                } else if model.isLoaded, !model.roots.isEmpty {
                    Text("\(count) items", comment: "Status bar: number of files shown")
                    Text(verbatim: "·").foregroundStyle(JGColor.textTertiary)
                    Text(verbatim: ByteCountFormatter.string(fromByteCount: model.totalBytes, countStyle: .file))
                }
            }
            .foregroundStyle(JGColor.textSecondary)
            Spacer()
            if let problem = model.problem {
                problemText(problem)
                    .foregroundStyle(JGColor.danger)
                Button {
                    model.problem = nil
                } label: {
                    Image(systemName: "xmark")
                        .foregroundStyle(JGColor.textTertiary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("Dismiss"))
            } else if let activity = model.activity {
                Group {
                    switch activity {
                    case .indexing: Text("Indexing…", comment: "Status bar: scanning folders")
                    case .readingDetails: Text("Reading details…", comment: "Status bar: reading dimensions, durations, dates")
                    }
                }
                .foregroundStyle(JGColor.textTertiary)
            }
        }
        .jgTextStyle(.mono)
        .lineLimit(1)
        .padding(.horizontal, JGSpacing.m)
    }

    private func problemText(_ problem: LibraryModel.Problem) -> Text {
        switch problem {
        case .alreadyInLibrary: Text("This folder is already in the library.")
        case .overlapsLibraryFolder: Text("This folder is inside a library folder or contains one.")
        case .folderUnavailable: Text("The folder is not available.")
        }
    }
}
