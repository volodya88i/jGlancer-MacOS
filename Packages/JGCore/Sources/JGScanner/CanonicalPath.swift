import Darwin
import Foundation

/// Canonical file-system paths, as FSEvents reports them.
public enum CanonicalPath {
    /// The `realpath(3)` form of `url`: symlinks resolved, `/private` kept (unlike
    /// `URL.resolvingSymlinksInPath()`, which strips it and would never match FSEvents paths).
    public static func of(_ url: URL) -> String {
        guard let resolved = realpath(url.path, nil) else { return url.standardizedFileURL.path }
        defer { free(resolved) }
        return String(cString: resolved)
    }
}
