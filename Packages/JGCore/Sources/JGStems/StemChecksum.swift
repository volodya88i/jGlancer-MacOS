import CryptoKit
import Foundation

/// Checksums of the Core ML models for the Mac (release of volodya88i/jGlancer-models) and of files.
public enum StemModelChecksums {
    /// The release a model is in: Demucs in the first, RoFormer in the second (D-131).
    public static func release(of model: StemModelInfo) -> String {
        model.network == .vocals ? "models-mac-2" : "models-mac-1"
    }

    static func values(of model: StemModelInfo) -> (sha256: String, bytes: Int64) {
        switch (model.network, model.isFull) {
        case (.four, true): ("2a87f04fde88d550c02d80d650dc6208424997f84a39b415e5b27bdd04775e38", 102_628_377)
        case (.six, true): ("6520f19cd502b1ffad7dd733406bd5752aab78147628ac1dff7e7a3b067e410a", 67_050_079)
        case (.four, false): ("ef6970b56fdb75bf3e07f0482d1eec993a4939f04f4ff696214810a70b7a208d", 79_318_777)
        case (.six, false): ("c38883c93dde7c70f5e3df80434761de32cd178a10e85c889656e6118dc2b873", 51_882_684)
        case (.vocals, true): ("f7bfa77272cbf97ca695c81f48a9f0780d9406dfa238eece3bdeb91619038cdc", 848_369_602)
        case (.vocals, false): ("e4aa45925b7e40a0dbb43b4b2a4e6114e9de6c5c1ac390f5147c5ddee5fe165d", 423_369_234)
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
