import AppKit
import JGModel
import JGSettings
import Observation

/// Settings → Open With, saved in user defaults (not for benchmark runs), and the entries of the Open With
/// submenus (docs/FEATURES.md §9, ARCHITECTURE §16).
@MainActor
@Observable
final class OpenWithStore {
    private(set) var settings: OpenWithSettings
    @ObservationIgnored private let isPersistent: Bool
    private static let key = "OpenWithSettings"

    init(isPersistent: Bool) {
        self.isPersistent = isPersistent
        settings = (isPersistent ? UserDefaults.standard.data(forKey: Self.key) : nil)
            .flatMap { try? JSONDecoder().decode(OpenWithSettings.self, from: $0) } ?? OpenWithSettings()
    }

    func update(_ change: (inout OpenWithSettings) -> Void) {
        change(&settings)
        if isPersistent, let data = try? JSONEncoder().encode(settings) {
            UserDefaults.standard.set(data, forKey: Self.key)
        }
    }

    /// An app bundle as an `ExternalApp`; nil for something that is not an app.
    static func externalApp(at url: URL) -> ExternalApp? {
        guard let bundle = Bundle(url: url), let id = bundle.bundleIdentifier else { return nil }
        return ExternalApp(bundleID: id, path: url.path, name: appName(url))
    }

    /// An app's name as Finder shows it, without ".app".
    static func appName(_ url: URL) -> String {
        let name = FileManager.default.displayName(atPath: url.path)
        return name.hasSuffix(".app") ? String(name.dropLast(4)) : name
    }

    /// Where a configured app is now: by bundle id, else its saved path; nil when uninstalled.
    static func location(of app: ExternalApp) -> URL? {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app.bundleID) {
            return url
        }
        return FileManager.default.fileExists(atPath: app.path) ? URL(fileURLWithPath: app.path) : nil
    }

    // MARK: Submenu entries

    enum Entry: Hashable {
        /// `url` is nil for a configured app that is no longer installed.
        case app(name: String, url: URL?, isPrimary: Bool, isDefault: Bool)
        case separator
        case other
    }

    /// Configured apps of `kind` (primary first), then the apps macOS offers for `sample` (its default first),
    /// then Other….
    func entries(for kind: MediaKind?, sample: URL?) -> [Entry] {
        let configured = kind.map { settings.apps(for: $0) } ?? []
        let primary = kind.flatMap { settings.primary(for: $0) }
        var entries = configured.map { app in
            Entry.app(name: app.name, url: Self.location(of: app), isPrimary: app == primary, isDefault: false)
        }
        // Every copy of this app is left out (a debug build and an installed one have the same id).
        let excludedIDs = Set(configured.map(\.bundleID) + [Bundle.main.bundleIdentifier ?? ""])
        if let sample {
            let defaultApp = NSWorkspace.shared.urlForApplication(toOpen: sample)?.standardizedFileURL
            let suggested = NSWorkspace.shared.urlsForApplications(toOpen: sample)
                .map(\.standardizedFileURL)
                .filter { !excludedIDs.contains(Bundle(url: $0)?.bundleIdentifier ?? "") }
                .sorted { ($0 == defaultApp ? 0 : 1, $0.lastPathComponent) < ($1 == defaultApp ? 0 : 1, $1.lastPathComponent) }
            if !entries.isEmpty, !suggested.isEmpty {
                entries.append(.separator)
            }
            entries += suggested.map { url in
                .app(
                    name: Self.appName(url), url: url, isPrimary: false,
                    isDefault: url == defaultApp
                )
            }
        }
        if !entries.isEmpty {
            entries.append(.separator)
        }
        entries.append(.other)
        return entries
    }
}
