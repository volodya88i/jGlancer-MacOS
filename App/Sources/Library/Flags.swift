import AppKit
import JGDesign
import JGModel
import JGStore
import Observation
import SwiftUI

/// Where views read flags (docs/FEATURES.md §12, DECISIONS D-57): the store, and a version that changes after every
/// flag change, so stars outside the grid refresh.
@MainActor
@Observable
final class FlagBook {
    private(set) var version = 0
    @ObservationIgnored var store: LibraryStore?

    func changed() {
        version += 1
    }

    func flag(of assetID: Int64) async -> AssetFlag {
        guard let store else { return .none }
        return await (try? store.flags(ids: [assetID]))?[assetID] ?? .none
    }
}

extension EnvironmentValues {
    @Entry var flagBook: FlagBook?
}

extension AssetFlag {
    /// The star's color.
    var token: JGColorToken {
        switch self {
        case .none, .accent: JGColor.accentText
        case .red: JGColor.flagRed
        case .orange: JGColor.flagOrange
        case .yellow: JGColor.flagYellow
        case .green: JGColor.flagGreen
        case .blue: JGColor.flagBlue
        case .purple: JGColor.flagPurple
        }
    }

    var title: String {
        switch self {
        case .none: String(localized: "Remove Flag", comment: "Flag menu: removes the flag")
        case .accent: String(localized: "Accent Color", comment: "Flag menu: flag in the app's accent color")
        case .red: String(localized: "Red", comment: "Flag color")
        case .orange: String(localized: "Orange", comment: "Flag color")
        case .yellow: String(localized: "Yellow", comment: "Flag color")
        case .green: String(localized: "Green", comment: "Flag color")
        case .blue: String(localized: "Blue", comment: "Flag color")
        case .purple: String(localized: "Purple", comment: "Flag color")
        }
    }

    /// The flags of the menus in order: accent, the six colors, then Remove Flag.
    static let menuOrder: [AssetFlag] = [.accent] + colors + [.none]

    /// A colored star for AppKit menus and tile badges (not a template image), cached per flag, size and theme.
    @MainActor
    func starImage(pointSize: CGFloat, appearance: NSAppearance) -> NSImage? {
        let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        let key = "\(rawValue)-\(pointSize)-\(isDark)"
        if let cached = FlagImages.cache[key] {
            return cached
        }
        var color = NSColor.systemPurple
        appearance.performAsCurrentDrawingAppearance {
            color = token.nsColor.usingColorSpace(.sRGB) ?? color
        }
        let configuration = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [color]))
        let image = NSImage(systemSymbolName: self == .none ? "star.slash" : "star.fill", accessibilityDescription: title)?
            .withSymbolConfiguration(configuration)
        FlagImages.cache[key] = image
        return image
    }
}

@MainActor
private enum FlagImages {
    static var cache: [String: NSImage] = [:]
}

/// The flag star of a library file beside its name (viewers, preview pane); nothing when unflagged or outside
/// the library.
struct FlagStar: View {
    let assetID: Int64?
    @Environment(\.flagBook) private var book
    @State private var flag = AssetFlag.none

    var body: some View {
        Group {
            if flag != .none {
                Image(systemName: "star.fill")
                    .font(.system(size: JGTextStyle.body.size, weight: .semibold))
                    .foregroundStyle(flag.token)
                    .accessibilityLabel(Text("Flag: \(flag.title)", comment: "Accessibility: the file's flag color"))
            }
        }
        .task(id: FlagKey(assetID: assetID, version: book?.version ?? 0)) {
            guard let assetID, assetID > 0, let book else {
                flag = .none
                return
            }
            flag = await book.flag(of: assetID)
        }
    }

    private struct FlagKey: Hashable {
        let assetID: Int64?
        let version: Int
    }
}
