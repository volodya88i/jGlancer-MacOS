import Foundation

/// Rename many files at once (docs/FEATURES.md §7): a template of text and the tokens `{name}` (the old name
/// without its extension), `{n}` (a counter) and `{date}` (capture or modification date, `yyyy-MM-dd`).
/// Extensions are kept unless `newExtension` names another one (the file is not converted, D-75).
public struct BatchRenamePattern: Equatable, Sendable {
    public static let nameToken = "{name}"
    public static let counterToken = "{n}"
    public static let dateToken = "{date}"

    public var template: String
    public var start: Int
    /// Counter digits with leading zeros; 0 uses as many as the last number needs.
    public var digits: Int
    /// The extension every file gets, with or without a leading dot; empty keeps each file's own.
    public var newExtension = ""

    public init(template: String = BatchRenamePattern.nameToken, start: Int = 1, digits: Int = 0) {
        self.template = template
        self.start = start
        self.digits = digits
    }

    /// One file of the batch.
    public struct File: Equatable, Sendable {
        public let url: URL
        public let date: Date

        public init(url: URL, date: Date) {
            self.url = url
            self.date = date
        }
    }

    /// Why a new name cannot be used.
    public enum Problem: Equatable, Sendable {
        case empty
        /// "/", ":" or a leading dot.
        case invalidCharacters
        /// Two files of the batch would get the same name in one folder.
        case duplicate
        /// Another file in the folder already has it.
        case taken
    }

    /// The new names, in the order of `files`.
    public func names(for files: [File]) -> [String] {
        let width = digits > 0 ? digits : String(start + max(files.count - 1, 0)).count
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return files.enumerated().map { index, file in
            let ext = replacementExtension ?? file.url.pathExtension
            let counter = String(start + index)
            let padded = String(repeating: "0", count: max(width - counter.count, 0)) + counter
            let base = template
                .replacingOccurrences(of: Self.nameToken, with: file.url.deletingPathExtension().lastPathComponent)
                .replacingOccurrences(of: Self.counterToken, with: padded)
                .replacingOccurrences(of: Self.dateToken, with: formatter.string(from: file.date))
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return base.isEmpty || ext.isEmpty ? base : base + "." + ext
        }
    }

    /// `newExtension` without spaces and leading dots; nil when it is empty (each file keeps its own).
    var replacementExtension: String? {
        let trimmed = newExtension.trimmingCharacters(in: .whitespacesAndNewlines)
        let bare = String(trimmed.drop { $0 == "." })
        return bare.isEmpty ? nil : bare
    }

    /// Problems per file (nil when the name is fine). `existing(folder)` lists the names already in a folder;
    /// names of the batch's own files do not count as taken. Names compare case-insensitively, as on APFS.
    public static func problems(
        files: [File], names: [String], existing: (URL) -> Set<String>
    ) -> [Problem?] {
        var counts: [String: Int] = [:]
        for (file, name) in zip(files, names) {
            counts[key(file, name), default: 0] += 1
        }
        let own = Set(files.map { key($0, $0.url.lastPathComponent) })
        var listed: [URL: Set<String>] = [:]
        return zip(files, names).map { file, name -> Problem? in
            let base = (name as NSString).deletingPathExtension.trimmingCharacters(in: .whitespaces)
            if base.isEmpty {
                return .empty
            }
            if name.contains("/") || name.contains(":") || name.hasPrefix(".") {
                return .invalidCharacters
            }
            if counts[key(file, name), default: 0] > 1 {
                return .duplicate
            }
            let folder = file.url.deletingLastPathComponent()
            let names = listed[folder] ?? Set(existing(folder).map { $0.lowercased() })
            listed[folder] = names
            if names.contains(name.lowercased()), !own.contains(key(file, name)) {
                return .taken
            }
            return nil
        }
    }

    private static func key(_ file: File, _ name: String) -> String {
        file.url.deletingLastPathComponent().path + "/" + name.lowercased()
    }
}
