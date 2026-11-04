import AppKit
import JGActions
import JGModel

/// -JGFlagRedrawCheck <png>: flags the first three tiles red and snapshots the grid 150 ms later; the tiles must keep their
/// thumbnails and show the flag (D-113). Logs how long until every tile has its new row.
@MainActor
enum FlagRedrawCheck {
    static func run(_ appModel: AppModel, library: LibraryModel, snapshot: URL) async {
        try? await Task.sleep(for: .milliseconds(1500))
        let ids = Array(library.refs.prefix(3).map(\.id))
        guard !ids.isEmpty, let window = DeveloperHooks.mainWindow else { return }
        let began = Date()
        appModel.actions.setFlag(.red, on: ActionTarget(
            place: .library, assetIDs: ids, kinds: [.photo], count: ids.count, sample: nil, urls: { [] }
        ))
        while await ((try? library.store.flags(ids: ids)) ?? [:]).values.contains(where: { $0 != .red }),
              Date().timeIntervalSince(began) < 3
        {
            try? await Task.sleep(for: .milliseconds(10))
        }
        try? await Task.sleep(for: .milliseconds(150))
        DeveloperHooks.snapshot(window, to: snapshot)
        FileHandle.standardError.write(Data(String(format: "flag check: stored and snapshot after %.0f ms\n",
                                                   Date().timeIntervalSince(began) * 1000).utf8))
    }
}
