/// Time codes for badges, scrubbers and players: `0:42`, `12:05`, `1:02:03`.
public enum DurationFormat {
    /// Positional time with no leading zero on the first unit; nil for negative or non-finite input.
    public static func positional(_ seconds: Double) -> String? {
        guard seconds.isFinite, seconds >= 0 else { return nil }
        let total = Int(seconds.rounded())
        let hours = total / 3600
        let minutes = total % 3600 / 60
        let remainder = total % 60
        return hours > 0
            ? "\(hours):\(twoDigits(minutes)):\(twoDigits(remainder))"
            : "\(minutes):\(twoDigits(remainder))"
    }

    /// Positional time with tenths (`1:02.3`), for segment ends; nil for negative or non-finite input.
    public static func tenths(_ seconds: Double) -> String? {
        guard seconds.isFinite, seconds >= 0 else { return nil }
        let tenths = Int((seconds * 10).rounded())
        return positional(Double(tenths / 10)).map { "\($0).\(tenths % 10)" }
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}
