import Foundation

/// A version number `x.y.z`, as the app and its releases name themselves (D-104). Anything else is refused, so an odd
/// answer from the network never becomes a version or part of an address.
public struct AppVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let major: Int
    public let minor: Int
    public let patch: Int

    /// From `1.2.3` (a leading `v` is allowed); nil for anything else.
    public init?(_ text: String) {
        var text = text
        if text.hasPrefix("v") {
            text.removeFirst()
        }
        let parts = text.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 3, parts.allSatisfy({ !$0.isEmpty && $0.count <= 6 && $0.allSatisfy(\.isASCII) && $0.allSatisfy(\.isNumber) }),
              let major = Int(parts[0]), let minor = Int(parts[1]), let patch = Int(parts[2])
        else { return nil }
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public var description: String {
        "\(major).\(minor).\(patch)"
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }
}

/// When the daily update check runs and what it offers (D-104).
public enum UpdatePolicy {
    /// At most once a day.
    public static let interval: TimeInterval = 24 * 60 * 60

    public static func isDue(lastCheck: Date?, now: Date) -> Bool {
        guard let lastCheck else { return true }
        return now.timeIntervalSince(lastCheck) >= interval || now < lastCheck
    }

    /// The release to offer: newer than the installed version; a skipped one only if `manual`.
    public static func offer(latest: AppVersion, installed: AppVersion, skipped: String?, manual: Bool) -> Bool {
        latest > installed && (manual || skipped != latest.description)
    }
}
