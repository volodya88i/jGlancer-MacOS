import AppKit
import Foundation
import JGActions
import JGModel

/// -JGCompareCheck <png>: Compare on the first two photos, a snapshot at fit and one at 100 % (linked), then swap,
/// unlink, a blocked action, and back with the left photo selected (logged).
@MainActor
enum CompareCheck {
    static func run(_ appModel: AppModel, library: LibraryModel, snapshot: URL) async {
        try? await Task.sleep(for: .milliseconds(600))
        let photos = library.refs.filter { $0.kind == .photo }.map(\.id)
        guard photos.count >= 2, let window = DeveloperHooks.mainWindow else {
            log("need two photos")
            return
        }
        await appModel.openCompare(Array(photos.prefix(2)))
        guard let model = appModel.compareModel else {
            log("compare did not open")
            return
        }
        try? await Task.sleep(for: .milliseconds(1500))
        log("sides: " + model.sides.map { "\($0.asset.name) \(Int($0.pixelSize.width))×\(Int($0.pixelSize.height))" }
            .joined(separator: ", "))
        DeveloperHooks.snapshot(window, to: snapshot)
        model.focusedSide = 1
        model.apply(.actualSize)
        model.changeZoom(of: 1) { $0.pan(by: CGVector(dx: 80, dy: 40), actualSize: $1, in: $2) }
        try? await Task.sleep(for: .milliseconds(1500))
        log("linked: left \(describe(model.zoom(of: 0))), right \(describe(model.zoom(of: 1))); "
            + "full resolution: \(model.sides.map(\.isFullResolution))")
        DeveloperHooks.snapshot(window, to: snapshot.deletingPathExtension().appendingPathExtension("zoomed.png"))
        model.apply(.swap)
        model.apply(.toggleLink)
        model.apply(.fit)
        log("swapped: \(model.sides.map(\.asset.name)); linked \(model.isLinked); focused \(model.focusedSide) "
            + "fit \(model.zoom(of: model.focusedSide).isFit), other fit \(model.zoom(of: 1 - model.focusedSide).isFit)")
        if let target = appModel.currentTarget {
            log("menu: \(appModel.actions.menu(for: target).joined().map(\.id.rawValue))")
        }
        let left = model.leftAssetID
        appModel.closeViewer()
        try? await Task.sleep(for: .milliseconds(400))
        log("back: selected left \(library.selection.selected == [left ?? -1])")
    }

    private static func describe(_ zoom: CompareZoom) -> String {
        String(format: "%.2f× (%.3f, %.3f)", zoom.scale, zoom.center.x, zoom.center.y)
    }

    private static func log(_ line: String) {
        FileHandle.standardError.write(Data("compare check: \(line)\n".utf8))
    }
}
