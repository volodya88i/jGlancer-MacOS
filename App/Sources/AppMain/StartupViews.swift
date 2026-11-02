import AppKit
import JGDesign
import JGStore
import SwiftUI

/// The library could not be opened at all: what happened and a way out, instead of an empty window.
struct StartupErrorView: View {
    let detail: String

    var body: some View {
        JGEmptyState(
            label: Text("Library", comment: "Section label of the library screen; shown in capitals"),
            title: AttributedString(localized: "The library **can't open**.", comment: "Startup error headline; ** marks the accent word"),
            message: Text(
                "Check that the disk with the library folder is connected and can be written to, then open the app again.",
                comment: "Startup error explanation"
            )
        ) {
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([AppPaths.libraryDatabase])
            } label: {
                Text("Reveal in Finder")
            }
            .buttonStyle(.jg(.secondary))
            Button {
                NSApp.terminate(nil)
            } label: {
                Text("Quit", comment: "Startup error: quits the app")
            }
            .buttonStyle(.jg(.primary))
        }
        .overlay(alignment: .bottomLeading) {
            // The technical cause, for a bug report.
            Text(verbatim: detail)
                .jgTextStyle(.mono)
                .foregroundStyle(JGColor.textTertiary)
                .textSelection(.enabled)
        }
        .padding(JGSpacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(JGColor.bgBase)
    }
}

/// The library was damaged at launch: one banner that says what was done and where the damaged file is.
struct RecoveryBanner: View {
    let recovery: LibraryRecovery
    let dismiss: () -> Void

    var body: some View {
        JGToast(
            message,
            actionTitle: Text("Reveal in Finder"),
            action: { NSWorkspace.shared.activateFileViewerSelecting([damagedCopy]) },
            dismiss: (Text("Close", comment: "Closes a message"), dismiss)
        )
    }

    private var message: Text {
        switch recovery {
        case let .restoredFromBackup(date, _):
            Text(
                "The library was damaged and is back from its copy of \(date.formatted(date: .abbreviated, time: .shortened)).",
                comment: "Startup recovery banner; the argument is the backup's date"
            )
        case .startedEmpty:
            Text(
                "The library was damaged; a new one was started.",
                comment: "Startup recovery banner without a backup"
            )
        }
    }

    private var damagedCopy: URL {
        switch recovery {
        case let .restoredFromBackup(_, url), let .startedEmpty(url): url
        }
    }
}
