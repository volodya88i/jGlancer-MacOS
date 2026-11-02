import AppKit
import JGModel

/// `-JGFlagCheck YES` with `-JGSelect N`: presses ⌃F then 1 (as the keyboard would), turns the star
/// filter on, presses it again (the flag comes off), undoes, and logs flags and the filtered count at each step.
/// Leaves the red flags and the filter on for a snapshot. Test libraries only.
@MainActor
enum FlagCheck {
    static func run(appModel: AppModel, library: LibraryModel) async {
        let ids = Array(library.selection.selected)
        await press("1", appModel)
        await log("after ⌃F 1: \(flags(library, ids))")
        library.setFlagFilter(.flagged)
        try? await Task.sleep(for: .milliseconds(500))
        log("filter flagged: \(library.refs.count) shown")
        await press("1", appModel)
        await log("after ⌃F 1 again: \(flags(library, ids)), shown \(library.refs.count)")
        appModel.fileOps?.undo()
        try? await Task.sleep(for: .milliseconds(500))
        await log("after undo: \(flags(library, ids)), shown \(library.refs.count)")
    }

    /// Flags the selection red again and turns the filter off, for a snapshot of the stars.
    static func leaveRedFlags(appModel: AppModel, library: LibraryModel) async {
        if let target = library.actionTarget(sample: nil) {
            appModel.actions.setFlag(.red, on: target)
        }
        library.setFlagFilter(nil)
        try? await Task.sleep(for: .milliseconds(600))
    }

    /// ⌃F, then ⌃`digit` (control still held), sent through `NSApp.sendEvent` like real key presses.
    private static func press(_ digit: String, _: AppModel) async {
        let codes = ["0": 29, "1": 18, "2": 19]
        for (key, code) in [("f", 3), (digit, codes[digit] ?? 18)] {
            if let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: .control, timestamp: 0,
                windowNumber: DeveloperHooks.mainWindow?.windowNumber ?? 0, context: nil, characters: key,
                charactersIgnoringModifiers: key, isARepeat: false, keyCode: UInt16(code)
            ) {
                NSApp.sendEvent(event)
            }
            try? await Task.sleep(for: .milliseconds(100))
        }
        log("pressed ⌃F \(digit)")
        try? await Task.sleep(for: .milliseconds(600))
    }

    private static func flags(_ library: LibraryModel, _ ids: [Int64]) async -> [String] {
        let flags = await (try? library.store.flags(ids: ids)) ?? [:]
        return ids.map { "\(flags[$0] ?? .none)" }
    }

    private static func log(_ line: String) {
        FileHandle.standardError.write(Data("flag check: \(line)\n".utf8))
    }
}
