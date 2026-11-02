import Foundation

/// A run of numbered frames in one folder that the grid can fold into one tile (D-84, W-81).
public struct ImageSequence: Hashable, Sendable {
    /// The first frame: the tile that stands for the run.
    public var head: Int64 {
        frames[0]
    }

    /// Every frame, by number (head first).
    public let frames: [Int64]

    public init(frames: [Int64]) {
        precondition(!frames.isEmpty, "a sequence has frames")
        self.frames = frames
    }
}

/// Finds image sequences: at least `minimumLength` photos in one folder with the same prefix and extension and
/// consecutive numbers (`render_001.png … render_090.png`); a gap starts a new run. Camera names (IMG, DSC, PXL…)
/// never fold: their numbers count shots, not frames.
public enum ImageSequences {
    public static let minimumLength = 5

    /// Prefixes of camera and phone file names, compared case-insensitively without trailing separators.
    public static let cameraPrefixes: Set<String> = [
        "img", "dsc", "dscn", "dscf", "dji", "gopr", "gp", "gh", "gx", "pxl", "mvi", "vid", "cimg", "sam", "pano",
        "hpim", "photo", "screenshot", "image",
    ]

    /// A photo that may belong to a sequence.
    public struct Member: Sendable {
        public let id: Int64
        public let folderID: Int64
        public let name: String

        public init(id: Int64, folderID: Int64, name: String) {
            self.id = id
            self.folderID = folderID
            self.name = name
        }
    }

    /// The sequences among `members` (any order).
    public static func find(in members: [Member]) -> [ImageSequence] {
        var groups: [Key: [(number: Int, id: Int64)]] = [:]
        for member in members {
            guard let (key, number) = parse(member) else { continue }
            groups[key, default: []].append((number, member.id))
        }
        var sequences: [ImageSequence] = []
        for frames in groups.values {
            var run: [Int64] = []
            var last: Int?
            for frame in frames.sorted(by: { $0.number < $1.number }) {
                if let last, frame.number == last + 1 {
                    run.append(frame.id)
                } else {
                    if run.count >= minimumLength {
                        sequences.append(ImageSequence(frames: run))
                    }
                    run = [frame.id]
                }
                last = frame.number
            }
            if run.count >= minimumLength {
                sequences.append(ImageSequence(frames: run))
            }
        }
        return sequences.sorted { $0.head < $1.head }
    }

    private struct Key: Hashable {
        let folderID: Int64
        let prefix: String
        let fileExtension: String
    }

    /// "render_012.png" → (folder, "render_", "png"), 12; nil without a trailing number or for camera names.
    private static func parse(_ member: Member) -> (Key, Int)? {
        let name = member.name as NSString
        let base = name.deletingPathExtension
        let digits = base.reversed().prefix { $0.isASCII && $0.isNumber }
        guard !digits.isEmpty, digits.count <= 9, let number = Int(String(digits.reversed())) else { return nil }
        let prefix = String(base.dropLast(digits.count))
        let bare = prefix.trimmingCharacters(in: CharacterSet(charactersIn: " _-.")).lowercased()
        guard !cameraPrefixes.contains(bare) else { return nil }
        return (Key(folderID: member.folderID, prefix: prefix.lowercased(), fileExtension: name.pathExtension.lowercased()), number)
    }
}
