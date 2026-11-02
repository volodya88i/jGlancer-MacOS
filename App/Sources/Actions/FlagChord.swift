import AppKit
import Carbon.HIToolbox
import JGActions
import JGModel

/// Flag keys: the Flag Accent shortcut (⌃F by default) followed by a digit — 1–6 a color,
/// 0 removes — within `window`; with no digit the accent flag is set. Keys go by position, so any layout.
@MainActor
final class FlagChord {
    private weak var appModel: AppModel?
    private var monitor: Any?
    private var pending: Task<Void, Never>?
    private static let window = Duration.milliseconds(700)
    private static let digits: [Int: Int] = [
        kVK_ANSI_0: 0, kVK_ANSI_1: 1, kVK_ANSI_2: 2, kVK_ANSI_3: 3, kVK_ANSI_4: 4, kVK_ANSI_5: 5, kVK_ANSI_6: 6,
    ]

    init(appModel: AppModel) {
        self.appModel = appModel
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            self?.handle(event) == true ? nil : event
        }
    }

    private func handle(_ event: NSEvent) -> Bool {
        guard let appModel, !(NSApp.keyWindow?.firstResponder is NSText) else { return false }
        if pending != nil, let digit = Self.digits[Int(event.keyCode)],
           event.modifierFlags.isDisjoint(with: [.command, .option])
        {
            pending?.cancel()
            pending = nil
            apply(digit == 0 ? AssetFlag.none : AssetFlag.colors[digit - 1])
            return true
        }
        guard let shortcut = appModel.shortcuts.shortcut(for: .flagAccent),
              ActionShortcut(event: event) == shortcut, appModel.currentTarget != nil
        else { return false }
        pending?.cancel()
        pending = Task { [weak self] in
            try? await Task.sleep(for: Self.window)
            guard !Task.isCancelled else { return }
            self?.pending = nil
            self?.apply(.accent)
        }
        return true
    }

    private func apply(_ flag: AssetFlag) {
        guard let appModel, let target = appModel.currentTarget else { return }
        appModel.actions.setFlag(flag, on: target)
    }
}
