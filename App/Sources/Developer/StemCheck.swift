import AppKit
import Foundation
import JGStems

/// -JGStemCheck <png> with -JGStemModels <folder of compiled .mlmodelc> (and -JGDataDirectory): installs the models
/// into the data folder, opens Split into Stems on the first song (snapshot of the sheet), splits it into 4 stems and
/// logs the files, the time and the toast. Never undoes (that would fill the Trash).
@MainActor
enum StemCheck {
    static func run(_ appModel: AppModel, library: LibraryModel, snapshot: URL) async {
        try? await Task.sleep(for: .seconds(1))
        let stems = appModel.stems
        if let models = DeveloperHooks.defaults.string(forKey: "JGStemModels") {
            try? FileManager.default.createDirectory(at: stems.store.folder, withIntermediateDirectories: true)
            for model in StemModelInfo.all where !stems.store.isInstalled(model) {
                try? FileManager.default.copyItem(
                    at: URL(fileURLWithPath: models).appendingPathComponent(model.name + ".mlmodelc"), to: stems.store.compiledURL(model)
                )
            }
        }
        guard let song = library.refs.first(where: { $0.kind == .audio }),
              let asset = try? await library.store.assets(ids: [song.id]).first,
              let window = DeveloperHooks.mainWindow
        else {
            log("no song")
            return
        }
        let url = asset.url
        await appModel.requestStemSplit(ActionTarget(
            place: .library, assetIDs: [song.id], kinds: [.audio], count: 1, sample: url, urls: { [url] }
        ))
        try? await Task.sleep(for: .milliseconds(800))
        if let sheet = window.attachedSheet {
            DeveloperHooks.snapshot(sheet, to: snapshot)
        }
        log("sheet open \(stems.request != nil), models installed 4: \(stems.isInstalled(.four)) 6: \(stems.isInstalled(.six))")
        stems.request = nil
        try? await Task.sleep(for: .milliseconds(400))
        let began = Date()
        stems.split([url], into: nil)
        try? await Task.sleep(for: .milliseconds(300))
        DeveloperHooks.snapshot(window, to: snapshot.deletingPathExtension().appendingPathExtension("progress.png"))
        while stems.running != nil {
            try? await Task.sleep(for: .milliseconds(100))
        }
        let folder = StemNaming.defaultFolder(for: url) { _ in false }
        let files = (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.sorted() ?? []
        log(String(format: "split in %.1f s: %@; toast \"%@\"", Date().timeIntervalSince(began), files.joined(separator: ", "),
                   appModel.fileOps?.toast?.message ?? "-"))
    }

    private static func log(_ line: String) {
        FileHandle.standardError.write(Data("stem check: \(line)\n".utf8))
    }
}
