import CryptoKit
import Foundation
import JGStore

/// A cheap content fingerprint for identity matching (docs/ARCHITECTURE.md §13):
/// SHA-256 over the size and the first and last 64 KB, truncated to 16 bytes.
public enum QuickHash {
    /// Bytes read from each end of the file.
    public static let sampleSize = 64 * 1024

    /// The fingerprint of the file at `url`, or nil if it cannot be read.
    public static func compute(url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        var hasher = SHA256()
        withUnsafeBytes(of: size.littleEndian) { hasher.update(bufferPointer: $0) }
        do {
            try handle.seek(toOffset: 0)
            if let head = try handle.read(upToCount: sampleSize) {
                hasher.update(data: head)
            }
            if size > UInt64(sampleSize) {
                try handle.seek(toOffset: max(UInt64(sampleSize), size - UInt64(sampleSize)))
                if let tail = try handle.read(upToCount: sampleSize) {
                    hasher.update(data: tail)
                }
            }
        } catch {
            return nil
        }
        return Data(hasher.finalize().prefix(16))
    }
}

/// The real file system, as seen by the store's identity matching.
public struct DiskFileProbe: FileProbe {
    public init() {}

    public func fileExists(atPath path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }

    public func quickHash(atPath path: String) -> Data? {
        QuickHash.compute(url: URL(fileURLWithPath: path))
    }
}
