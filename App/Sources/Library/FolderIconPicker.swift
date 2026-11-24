import AppKit
import JGDesign
import JGModel
import SwiftUI
import UniformTypeIdentifiers

/// Folder Icon… (D-129): a library folder's own icon. A symbol from the grid, an emoji (typed, or from the system's
/// Emoji & Symbols), or a photo from disk; Default brings the disk back. Each choice applies at once.
struct FolderIconPicker: View {
    let model: LibraryModel
    let root: RootFolder
    @State private var emoji = ""
    @FocusState private var isEmojiFocused: Bool
    @Environment(\.dismiss) private var dismiss

    /// The symbols offered: folders and places, media, and a few marks.
    static let symbols = [
        "externaldrive", "internaldrive", "folder", "tray.full", "archivebox", "shippingbox", "house", "desktopcomputer",
        "laptopcomputer", "icloud", "photo", "photo.on.rectangle", "camera", "camera.aperture", "film", "video",
        "tv", "music.note", "music.note.list", "headphones", "guitars", "pianokeys", "mic", "waveform",
        "star", "heart", "bookmark", "tag", "flag", "bolt", "flame", "sparkles",
        "leaf", "sun.max", "moon", "cloud", "snowflake", "airplane", "car", "globe",
        "map", "person", "person.2", "pawprint", "gamecontroller", "paintpalette", "book", "gift",
    ]

    private static let columns = 8

    var body: some View {
        VStack(alignment: .leading, spacing: JGSpacing.m) {
            header
            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(minimum: JGMetrics.controlHeight), spacing: JGSpacing.xxs),
                    count: Self.columns
                ),
                spacing: JGSpacing.xxs
            ) {
                ForEach(Self.symbols, id: \.self) { name in
                    symbolButton(name)
                }
            }
            HStack(spacing: JGSpacing.xs) {
                TextField(text: $emoji) {
                    Text("Emoji", comment: "Folder icon: the field that takes an emoji")
                }
                .textFieldStyle(.roundedBorder)
                .frame(width: JGMetrics.controlHeight * 2)
                .focused($isEmojiFocused)
                .onChange(of: emoji) { useEmoji() }
                Button {
                    isEmojiFocused = true
                    NSApp.orderFrontCharacterPalette(nil)
                } label: {
                    Text("Emoji & Symbols", comment: "Folder icon: opens the system's emoji picker")
                }
                .buttonStyle(.jg(.tertiary))
                Spacer(minLength: 0)
                Button(action: choosePhoto) {
                    Text("Choose Photo…", comment: "Folder icon: a picture file from disk")
                }
                .buttonStyle(.jg(.secondary))
            }
            HStack {
                Button {
                    model.setRootIcon(nil, for: root.id)
                } label: {
                    Text("Default", comment: "Folder icon: back to the disk icon")
                }
                .buttonStyle(.jg(.tertiary))
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Text("Done", comment: "Closes a sheet whose changes already apply")
                }
                .buttonStyle(.jg(.primary))
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(JGSpacing.l)
        .frame(width: JGMetrics.previewPaneMaxWidth)
        .background(JGColor.bgPanel)
    }

    private var header: some View {
        HStack(spacing: JGSpacing.s) {
            FolderIconView(icon: model.rootIcons[root.id], fallback: "externaldrive", isSelected: true, side: JGMetrics.controlHeight)
            VStack(alignment: .leading, spacing: 0) {
                Text("Folder Icon", comment: "Title of the sheet that chooses a library folder's icon")
                    .jgTextStyle(.heading)
                    .foregroundStyle(JGColor.textPrimary)
                Text(verbatim: URL(fileURLWithPath: root.path).lastPathComponent)
                    .jgTextStyle(.body)
                    .foregroundStyle(JGColor.textSecondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
    }

    private func symbolButton(_ name: String) -> some View {
        let isCurrent = if case let .symbol(current) = model.rootIcons[root.id] {
            current == name
        } else {
            false
        }
        return Button {
            model.setRootIcon(.symbol(name), for: root.id)
        } label: {
            Image(systemName: name)
                .font(.system(size: JGTextStyle.body.size + 2))
                .foregroundStyle(isCurrent ? JGColor.textPrimary : JGColor.textSecondary)
                .frame(width: JGMetrics.controlHeight, height: JGMetrics.controlHeight)
                .background(isCurrent ? JGColor.bgRaised : JGColor.bgPanel, in: JGShape(.small))
                .contentShape(JGShape(.small))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(verbatim: name))
    }

    /// The last emoji typed or picked becomes the icon; the field keeps only it.
    private func useEmoji() {
        guard let character = emoji.last(where: Self.isEmoji) else { return }
        let text = String(character)
        if emoji != text {
            emoji = text
        }
        model.setRootIcon(.emoji(text), for: root.id)
    }

    /// Emoji shown as pictures (a digit or # alone is not one).
    nonisolated static func isEmoji(_ character: Character) -> Bool {
        let scalars = character.unicodeScalars
        guard let first = scalars.first else { return false }
        return scalars.contains { $0.properties.isEmojiPresentation } || (first.properties.isEmoji && scalars.count > 1)
    }

    private func choosePhoto() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "Choose", comment: "Folder panel button")
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            MainActor.assumeIsolated {
                model.setRootIcon(fromFile: url, for: root.id)
            }
        }
    }
}
