import Foundation

/// Dates are stored as integer milliseconds since 1970 (DECISIONS D-29): exact equality
/// for change detection, still compact.
extension Date {
    var millisecondsSince1970: Int64 {
        Int64((timeIntervalSince1970 * 1000).rounded())
    }

    init(millisecondsSince1970 milliseconds: Int64) {
        self.init(timeIntervalSince1970: Double(milliseconds) / 1000)
    }
}
