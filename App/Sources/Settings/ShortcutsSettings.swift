import AppKit
import JGActions
import JGDesign
import JGModel
import SwiftUI

/// Settings → Shortcuts: every menu command with its shortcut. Click a shortcut and press the new keys (with ⌘ or
/// ⌃); Delete removes it, Esc cancels. A shortcut another command had moves over, and the line under the list says
/// so.
struct ShortcutsSettings: View {
    let store: ShortcutStore
    @State private var recording: ShortcutCommand?
    @State private var note: Text?

    var body: some View {
        group(Text("Files", comment: "Settings → Shortcuts group; shown in capitals"), ShortcutCommand.files)
        group(Text("Flags", comment: "Settings → Shortcuts group; shown in capitals"), ShortcutCommand.flags)
        group(Text("Library", comment: "Back button of the viewer; returns to the library"), ShortcutCommand.library)
        HStack {
            if let note {
                note.jgTextStyle(.body).foregroundStyle(JGColor.textSecondary)
            } else {
                Text("Click a shortcut, then press the keys. Delete removes it.", comment: "Settings → Shortcuts: how to change")
                    .jgTextStyle(.body)
                    .foregroundStyle(JGColor.textTertiary)
            }
            Spacer()
            Button {
                store.update { $0.resetAll() }
                note = nil
            } label: {
                Text("Restore Defaults", comment: "Settings → Shortcuts")
            }
            .buttonStyle(.jg(.tertiary))
            .disabled(store.map == ShortcutMap())
        }
    }

    private func group(_ title: Text, _ commands: [ShortcutCommand]) -> some View {
        SettingsGroup(title: title) {
            VStack(spacing: 0) {
                ForEach(commands, id: \.self) { command in
                    row(command)
                    if command != commands.last {
                        JGHairline()
                    }
                }
            }
        }
    }

    private func row(_ command: ShortcutCommand) -> some View {
        HStack(spacing: JGSpacing.s) {
            ShortcutNames.title(for: command)
                .jgTextStyle(.body)
                .foregroundStyle(JGColor.textPrimary)
            Spacer()
            if store.map.isCustomized(command) {
                Button {
                    store.update { $0.reset(command) }
                    note = nil
                } label: {
                    Image(systemName: "arrow.uturn.backward")
                        .font(.system(size: JGTextStyle.mono.size, weight: .semibold))
                        .foregroundStyle(JGColor.textTertiary)
                        .frame(width: JGMetrics.controlHeightCompact, height: JGMetrics.controlHeightCompact)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help(Text("Restore Default", comment: "Settings → Shortcuts: one command back to its default"))
                .accessibilityLabel(Text("Restore Default", comment: "Settings → Shortcuts: one command back to its default"))
            }
            ShortcutRecorder(
                shortcut: store.shortcut(for: command),
                isRecording: Binding(get: { recording == command }, set: { recording = $0 ? command : nil })
            ) { shortcut in
                record(shortcut, for: command)
            }
        }
        .frame(height: JGMetrics.controlHeight)
    }

    private func record(_ shortcut: ActionShortcut?, for command: ShortcutCommand) {
        switch store.update({ $0.assign(shortcut, to: command) }) {
        case let .assigned(takenFrom?):
            note = Text(
                "Taken from “\(ShortcutNames.string(for: takenFrom))”, which now has none.",
                comment: "Settings → Shortcuts: the shortcut moved from another command"
            )
        case .assigned:
            note = nil
        case .needsCommandOrControl:
            note = Text("Use ⌘ or ⌃ with the key.", comment: "Settings → Shortcuts: a shortcut needs Command or Control")
        case .reserved:
            note = Text("macOS or the app already uses these keys.", comment: "Settings → Shortcuts: a reserved shortcut")
        }
    }
}

/// The shortcut of one command as a small key cap; while recording it takes the next key press.
private struct ShortcutRecorder: View {
    let shortcut: ActionShortcut?
    @Binding var isRecording: Bool
    let set: (ActionShortcut?) -> Void
    @State private var monitor: Any?

    var body: some View {
        Button { isRecording.toggle() } label: {
            Group {
                if isRecording {
                    Text("Press keys…", comment: "Settings → Shortcuts: waiting for a key press")
                        .jgTextStyle(.body)
                        .foregroundStyle(JGColor.accentText)
                } else {
                    Text(verbatim: shortcut?.displayString ?? "—")
                        .jgTextStyle(.mono)
                        .foregroundStyle(shortcut == nil ? JGColor.textTertiary : JGColor.textPrimary)
                }
            }
            .padding(.horizontal, JGSpacing.s)
            .frame(minWidth: JGMetrics.shortcutCapWidth, minHeight: JGMetrics.controlHeightCompact)
            .background(JGColor.bgRaised, in: JGShape(.small))
            .overlay {
                JGShape(.small).strokeBorder(
                    isRecording ? JGColor.accent : JGColor.lineHair,
                    lineWidth: isRecording ? JGMetrics.selectionEdgeWidth : JGMetrics.outlineWidth
                )
            }
            .contentShape(JGShape(.small))
        }
        .buttonStyle(.plain)
        .accessibilityValue(Text(verbatim: shortcut?.displayString ?? ""))
        .onChange(of: isRecording) { _, recording in
            recording ? start() : stop()
        }
        .onDisappear(perform: stop)
    }

    /// Takes key presses before the menus do, so ⌘O is recorded instead of opening a file.
    private func start() {
        stop()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            let plain = event.modifierFlags.isDisjoint(with: [.command, .control, .option, .shift])
            if plain, event.keyCode == 53 {
                isRecording = false
            } else if plain, event.specialKey == .delete || event.specialKey == .backspace {
                set(nil)
                isRecording = false
            } else if let shortcut = ActionShortcut(event: event) {
                set(shortcut)
                isRecording = false
            }
            return nil
        }
    }

    private func stop() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
    }
}

/// Command names in Settings → Shortcuts.
enum ShortcutNames {
    static func title(for command: ShortcutCommand) -> Text {
        Text(verbatim: string(for: command))
    }

    static func string(for command: ShortcutCommand) -> String {
        if let flag = command.flag {
            return flag == .none ? flag.title : String(localized: "Flag: \(flag.title)", comment: "Settings → Shortcuts: sets this flag")
        }
        return switch command {
        case .open: String(localized: "Open", comment: "Action: open the file")
        case .quickPreview: String(localized: "Quick Preview", comment: "Accessibility label of the Quick Preview window")
        case .compare: String(localized: "Compare", comment: "Action: two photos side by side")
        case .editInPrimaryApp: String(
                localized: "Edit in Primary App",
                comment: "Settings → Shortcuts: opens files in the primary external app"
            )
        case .moveTo: String(localized: "Move to…", comment: "Action")
        case .copyTo: String(localized: "Copy to…", comment: "Action")
        case .rename: String(localized: "Rename…", comment: "Action")
        default: moreFileStrings(for: command)
        }
    }

    private static func moreFileStrings(for command: ShortcutCommand) -> String {
        switch command {
        case .setAlbumCover: String(localized: "Use as Album Cover", comment: "Action")
        case .getInfo: String(localized: "Get Info", comment: "Action")
        case .revealInFinder: String(localized: "Reveal in Finder")
        case .copyPath: String(localized: "Copy Path", comment: "Action: copies the file paths as text")
        case .moveToTrash: String(localized: "Move to Trash", comment: "Action")
        default: libraryString(for: command)
        }
    }

    private static func libraryString(for command: ShortcutCommand) -> String {
        switch command {
        case .find: String(localized: "Find", comment: "Menu: focuses the search field")
        case .addFolder: String(localized: "Add Folder…")
        case .newAlbum: String(localized: "New Album", comment: "Default name of a new album")
        default: viewString(for: command)
        }
    }

    private static func viewString(for command: ShortcutCommand) -> String {
        switch command {
        case .togglePreview: String(localized: "Show Preview", comment: "View menu: the preview pane on the right")
        case .showNames: String(localized: "Show Names", comment: "View menu: names under thumbnails")
        case .toggleSplitView: String(localized: "Split View", comment: "View menu: two library panes side by side")
        case .asGrid: String(localized: "as Grid", comment: "View menu: thumbnails in a grid")
        case .asList: String(localized: "as List", comment: "View menu: files in a Finder-style list")
        case .toggleSizeMap: String(localized: "Show Size Map", comment: "View menu: the folder's files as rectangles by size")
        case .toggleSidebar: String(localized: "Show Sidebar", comment: "View menu: the folders and albums on the left")
        default: String(localized: "Include Subfolders")
        }
    }
}
