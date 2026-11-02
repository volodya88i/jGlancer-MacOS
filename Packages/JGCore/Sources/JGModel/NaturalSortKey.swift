/// Builds a key whose plain byte order equals natural file-name order.
///
/// Case and diacritics are folded, and every run of digits is left-padded to a fixed width,
/// so "img_2.jpg" sorts before "IMG_10.jpg". Stored in `asset.name_key` so SQLite can sort
/// with an index instead of a slow custom collation.
public enum NaturalSortKey {
    /// Digit runs are padded to this many characters; longer runs keep their length.
    public static let digitWidth = 12

    /// The sort key for `name`.
    public static func make(_ name: String) -> String {
        let folded = name.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
        var key = ""
        key.reserveCapacity(folded.count + digitWidth)
        var digits = ""
        func flushDigits() {
            guard !digits.isEmpty else { return }
            let trimmed = digits.drop { $0 == "0" }
            let significant = trimmed.isEmpty ? "0" : String(trimmed)
            if significant.count < digitWidth {
                key += String(repeating: "0", count: digitWidth - significant.count)
            }
            key += significant
            digits = ""
        }
        for character in folded {
            if character.isASCII, character.isNumber {
                digits.append(character)
            } else {
                flushDigits()
                key.append(character)
            }
        }
        flushDigits()
        return key
    }
}
