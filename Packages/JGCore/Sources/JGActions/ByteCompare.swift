import Foundation

/// Byte-for-byte comparison of two files (W-78). Find Duplicates finds copies by size and quick hash, and confirms
/// each with this before anything goes to the Trash.
public enum ByteCompare {
    /// Bytes read from each file per step.
    static let chunkSize = 1 << 20

    /// True when both files can be read and hold the same bytes; false when they differ or one cannot be read.
    public static func identical(_ first: URL, _ second: URL) -> Bool {
        guard first.standardizedFileURL != second.standardizedFileURL,
              let sizeA = try? first.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              let sizeB = try? second.resourceValues(forKeys: [.fileSizeKey]).fileSize, sizeA == sizeB,
              let handleA = try? FileHandle(forReadingFrom: first), let handleB = try? FileHandle(forReadingFrom: second)
        else { return false }
        defer {
            try? handleA.close()
            try? handleB.close()
        }
        do {
            while true {
                // nil at the end of the file; a read error throws.
                let chunkA = try handleA.read(upToCount: chunkSize) ?? Data()
                let chunkB = try handleB.read(upToCount: chunkSize) ?? Data()
                guard chunkA == chunkB else { return false }
                if chunkA.isEmpty {
                    return true
                }
            }
        } catch {
            return false
        }
    }
}
