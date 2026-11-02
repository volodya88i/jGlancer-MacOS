import Foundation

/// The single code-level source of the app's identity (CLAUDE.md, DECISIONS D-01).
///
/// The values themselves are defined once in `project.yml` and reach the app through Info.plist.
/// Nothing else in the code may spell the app's name or bundle identifier; the literals below
/// are fallbacks for contexts without a bundle (previews, tests).
enum AppIdentity {
    /// User-visible name, e.g. in window titles and the menu bar.
    static let name: String = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
        ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
        ?? "jGlancer"

    /// Bundle identifier.
    static let bundleIdentifier: String = Bundle.main.bundleIdentifier ?? "io.github.volodya88i.jglancer"

    /// Folder under `~/Library/Application Support` for `library.sqlite` and the originals vault.
    static var supportDirectoryName: String {
        name
    }

    /// Folder under `~/Library/Caches` for `cache.sqlite`.
    static var cachesDirectoryName: String {
        bundleIdentifier
    }
}
