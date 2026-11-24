import AppKit
import JGDesign
import SwiftUI

/// The viewers' top bar on frosted scrim (docs/DESIGN.md §8): back to the library, the file name, its position in the
/// folder in mono, then viewer-specific controls. Esc closes, or runs `onEscape` when given.
struct ViewerTopBar<Trailing: View>: View {
    let name: String
    let index: Int
    let count: Int
    /// The library file shown, for its flag star.
    var assetID: Int64?
    let onClose: () -> Void
    var onEscape: (() -> Void)?
    /// The filmstrip's lighter scrim, for the audio player's stage (WIN-027).
    var isLight = false
    @ViewBuilder let trailing: Trailing

    var body: some View {
        HStack(spacing: JGSpacing.m) {
            Button(action: onClose) {
                HStack(spacing: JGSpacing.xxs) {
                    Image(systemName: "chevron.left")
                    Text("Library", comment: "Back button of the viewer; returns to the library")
                }
            }
            .buttonStyle(.jg(.tertiary))
            .keyboardShortcut(onEscape == nil ? .cancelAction : nil)
            .background {
                if let onEscape {
                    Button("", action: onEscape)
                        .keyboardShortcut(.cancelAction)
                        .frame(width: 0, height: 0)
                        .opacity(0)
                        .accessibilityHidden(true)
                }
            }
            Text(verbatim: name)
                .jgTextStyle(.body)
                .foregroundStyle(JGColor.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)
            FlagStar(assetID: assetID)
            if count > 1 {
                Text(verbatim: "\(index + 1) / \(count)")
                    .jgTextStyle(.mono)
                    .foregroundStyle(JGColor.textSecondary)
            }
            Spacer(minLength: JGSpacing.m)
            trailing
        }
        .padding(.leading, WindowControlsRoom.shared.width)
        .padding(.trailing, JGSpacing.m)
        .frame(height: JGMetrics.barHeight)
        .background { Color.clear.contentShape(Rectangle()).titleBarDoubleClick() }
        // Blurs what is behind it like the bottom controls (D-109).
        .viewerGlass(tint: isLight ? JGMetrics.filmstripScrimOpacity : 1)
        .overlay(alignment: .bottom) { JGHairline() }
    }
}

/// A borderless icon button of the viewers; `isOn` tints it with the accent (loop on).
struct ViewerIconButton: View {
    let symbol: String
    let label: Text
    var isOn = false
    /// The tooltip, when it says more than the label.
    var help: Text?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: JGTextStyle.body.size))
                .foregroundStyle(isOn ? JGColor.accentText : JGColor.textPrimary)
                .frame(width: JGMetrics.controlHeight, height: JGMetrics.controlHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Space and Return keep their player meaning; they never press a focused button (D-77).
        .focusable(false)
        .help(help ?? label)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isOn ? .isSelected : [])
    }
}

/// "This folder isn't in the library." with Add Folder, for files opened from outside.
struct AddFolderButton: View {
    let onAdd: () -> Void

    var body: some View {
        Button(action: onAdd) {
            HStack(spacing: JGSpacing.xxs) {
                Image(systemName: "folder.badge.plus")
                Text("Add Folder", comment: "Adds the folder of the viewed file to the library")
            }
        }
        .buttonStyle(.jg(.tertiary))
        .help(Text("This folder isn't in the library.", comment: "Viewer offer for a file opened from outside the library"))
    }
}

/// A centered glyph and one short line (a file that cannot be shown), with optional actions below.
struct ViewerMessage<Actions: View>: View {
    let symbol: String
    let text: Text
    @ViewBuilder let actions: Actions

    var body: some View {
        VStack(spacing: JGSpacing.s) {
            Image(systemName: symbol)
                .font(.system(size: JGMetrics.tileGlyphSize, weight: .light))
                .foregroundStyle(JGColor.textTertiary)
                .accessibilityHidden(true)
            text
                .jgTextStyle(.body)
                .foregroundStyle(JGColor.textSecondary)
            actions
        }
    }
}

/// Hides viewer chrome after a short idle: one cancellable task per activity, no timers.
@MainActor
final class IdleHider {
    private var task: Task<Void, Never>?

    /// Calls `hide` after `JGMetrics.hudIdleSeconds` unless `schedule` or `cancel` comes first; when `hide`
    /// returns true (it hid something), the cursor hides too until the mouse moves.
    func schedule(hidesCursor: Bool = true, _ hide: @escaping @MainActor () -> Bool) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .seconds(JGMetrics.hudIdleSeconds))
            guard !Task.isCancelled else { return }
            if hide(), hidesCursor {
                NSCursor.setHiddenUntilMouseMoves(true)
            }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}

/// The one material of the viewers' bottom panels (filmstrip, scrubber and controls): frosted glass with a light
/// blur and a medium scrim tint, so media shows through but text stays readable. Opaque with Reduce Transparency.
struct ViewerGlass: ViewModifier {
    var tint = JGMetrics.glassTintOpacity
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        content.background {
            if reduceTransparency {
                Rectangle().fill(JGColor.bgPanel)
            } else {
                ZStack {
                    // Part-strength material: a softer blur than the system's thinnest.
                    Rectangle().fill(.ultraThinMaterial).opacity(JGMetrics.glassBlurOpacity)
                    Rectangle().fill(JGColor.overlayScrim).opacity(tint)
                }
            }
        }
    }
}

extension View {
    /// The viewers' frosted panel; `tint` is the scrim's strength over the blur.
    func viewerGlass(tint: Double = JGMetrics.glassTintOpacity) -> some View {
        modifier(ViewerGlass(tint: tint))
    }
}
