import JGModel

/// An external app the user chose for Open With (docs/FEATURES.md §9).
public struct ExternalApp: Codable, Hashable, Sendable {
    public let bundleID: String
    /// Where the app was when chosen (used if the bundle id no longer resolves).
    public let path: String
    public let name: String

    public init(bundleID: String, path: String, name: String) {
        self.bundleID = bundleID
        self.path = path
        self.name = name
    }
}

/// Settings → Open With: per kind, any number of apps and one primary (ARCHITECTURE §16). The first app added
/// to a kind becomes its primary; removing the primary promotes the next one.
public struct OpenWithSettings: Codable, Equatable, Sendable {
    private var apps: [MediaKind: [ExternalApp]] = [:]
    private var primaries: [MediaKind: String] = [:]

    public init() {}

    /// The kind's apps, primary first, then in the order they were added.
    public func apps(for kind: MediaKind) -> [ExternalApp] {
        let list = apps[kind] ?? []
        guard let primary = primary(for: kind) else { return list }
        return [primary] + list.filter { $0.bundleID != primary.bundleID }
    }

    public func primary(for kind: MediaKind) -> ExternalApp? {
        guard let id = primaries[kind] else { return nil }
        return apps[kind]?.first { $0.bundleID == id }
    }

    /// Kinds that have a primary app (for "Edit in …").
    public var kindsWithPrimary: Set<MediaKind> {
        Set(MediaKind.allCases.filter { primary(for: $0) != nil })
    }

    /// Adds `app` for `kind` (an app already there is updated, keeping its place).
    public mutating func add(_ app: ExternalApp, for kind: MediaKind) {
        var list = apps[kind] ?? []
        if let index = list.firstIndex(where: { $0.bundleID == app.bundleID }) {
            list[index] = app
        } else {
            list.append(app)
        }
        apps[kind] = list
        if primaries[kind] == nil {
            primaries[kind] = app.bundleID
        }
    }

    public mutating func remove(bundleID: String, for kind: MediaKind) {
        apps[kind]?.removeAll { $0.bundleID == bundleID }
        if primaries[kind] == bundleID {
            primaries[kind] = apps[kind]?.first?.bundleID
        }
    }

    public mutating func setPrimary(bundleID: String, for kind: MediaKind) {
        guard apps[kind]?.contains(where: { $0.bundleID == bundleID }) == true else { return }
        primaries[kind] = bundleID
    }
}
