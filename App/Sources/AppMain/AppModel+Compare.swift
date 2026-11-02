import AppKit
import JGActions
import JGModel

/// Compare (W-77): two selected photos side by side in place of the viewer.
extension AppModel {
    /// The Compare screen, when that is what is open.
    var compareModel: CompareModel? {
        if case let .compare(model) = viewer {
            model
        } else {
            nil
        }
    }

    /// Only these run while comparing; the rest would act on files the screen keeps showing.
    static let compareActions: Set<ActionID> = [.getInfo, .revealInFinder, .copyPath, .copy]

    func openCompare(_ ids: [Int64]) async {
        guard ids.count == 2, let library = activeLibrary,
              let assets = try? await library.store.assets(ids: ids), assets.count == 2, assets.allSatisfy({ $0.kind == .photo })
        else { return }
        // In the selection's order, not the store's.
        let ordered = ids.compactMap { id in assets.first { $0.id == id } }
        viewer = .compare(CompareModel(assets: ordered, thumbnails: library.thumbnails, screenPixels: Self.screenPixels))
    }

    /// Both photos (the top bar's Get Info, the menu bar), or one side (its context menu).
    func compareTarget(side: Int? = nil) -> ActionTarget? {
        guard let model = compareModel else { return nil }
        let assets = side.map { model.sides.indices.contains($0) ? [model.sides[$0].asset] : [] } ?? model.sides.map(\.asset)
        guard !assets.isEmpty else { return nil }
        let urls = assets.map(\.url)
        return ActionTarget(
            place: .viewer, assetIDs: assets.map(\.id), kinds: [.photo], count: assets.count, sample: urls.first,
            urls: { urls }
        )
    }

    func compareContextMenu(side: Int) -> NSMenu? {
        compareTarget(side: side).flatMap { ActionMenu.make(for: $0, performer: actions) }
    }

    func compareInfo() {
        if let target = compareTarget() {
            actions.perform(.getInfo, on: target)
        }
    }
}
