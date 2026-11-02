import CryptoKit
import Foundation

/// Checksums of the Core ML models for the Mac (release of volodya88i/jGlancer-models) and of files.
public enum StemModelChecksums {
    public static let release = "models-mac-1"

    static func values(of model: StemModelInfo) -> (sha256: String, bytes: Int64) {
        switch (model.mode, model.isFull) {
        case (.four, true): ("2a87f04fde88d550c02d80d650dc6208424997f84a39b415e5b27bdd04775e38", 102_628_377)
        case (.six, true): ("6520f19cd502b1ffad7dd733406bd5752aab78147628ac1dff7e7a3b067e410a", 67_050_079)
        case (.four, false): ("ef6970b56fdb75bf3e07f0482d1eec993a4939f04f4ff696214810a70b7a208d", 79_318_777)
        case (.six, false): ("c38883c93dde7c70f5e3df80434761de32cd178a10e85c889656e6118dc2b873", 51_882_684)
        }
    }
}

enum StemChecksum {
    /// The SHA-256 of a file, lower-case hex, read in 1 MB chunks.
    static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
