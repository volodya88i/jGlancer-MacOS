import AppKit
import SwiftUI

/// SwiftUI host of the AppKit grid. Reading the model's versioned properties in `body` makes SwiftUI
/// call `updateNSView` exactly when they change.
struct LibraryGridView: NSViewRepresentable {
    let model: LibraryModel
    /// Values the grid depends on, read here so changes trigger updates.
    let refsVersion: Int
    let selection: AnyHashable
    let tileSide: Double
    let showNames: Bool
    let focusRequest: Int
    let rowsVersion: Int
    let renameSerial: Int
    let crosshairs: Bool
    /// The bars over the grid (D-114): the files scroll under them and start and end clear of them.
    let insets: NSEdgeInsets

    init(model: LibraryModel, insets: NSEdgeInsets = NSEdgeInsets()) {
        self.insets = insets
        self.model = model
        refsVersion = model.refsVersion
        selection = AnyHashable(model.selection.selected)
        tileSide = model.state.tileSide
        showNames = model.state.showNames
        focusRequest = model.focusRequest
        rowsVersion = model.rowsVersion
        renameSerial = model.inlineRenameRequest?.serial ?? 0
        crosshairs = model.decorCrosshairs
    }

    func makeCoordinator() -> GridController {
        GridController(model: model)
    }

    func makeNSView(context: Context) -> NSScrollView {
        context.coordinator.scrollView
    }

    func updateNSView(_: NSScrollView, context: Context) {
        context.coordinator.setInsets(insets)
        context.coordinator.sync()
    }
}
