import Foundation
import JGModel
import os
import UniformTypeIdentifiers

/// Classifies files into media kinds by `UTType` conformance of their extension (docs/ARCHITECTURE.md §5).
///
/// Uses the extension only, as Finder does, and caches per extension: stage 1 never opens files.
public final class MediaClassifier: Sendable {
    /// A classified file type.
    public struct Classification: Hashable, Sendable {
        public let kind: MediaKind
        public let typeIdentifier: String
    }

    private let cache = OSAllocatedUnfairLock<[String: Classification?]>(initialState: [:])

    public init() {}

    /// The kind and type of a file name, or nil if it is not photo, video or audio.
    public func classify(fileName: String) -> Classification? {
        let pathExtension = (fileName as NSString).pathExtension.lowercased()
        guard !pathExtension.isEmpty else { return nil }
        if let cached = cache.withLock({ $0[pathExtension] }) {
            return cached
        }
        let result = Self.classify(pathExtension: pathExtension)
        cache.withLock { $0[pathExtension] = .some(result) }
        return result
    }

    /// Common formats macOS does not declare as movie/audio types. They are indexed so the viewer can show
    /// "can't play here — Open With…" instead of hiding the file (DECISIONS D-10, D-30).
    static let undeclaredKinds: [String: MediaKind] = [
        "mkv": .video, "webm": .video, "avi": .video, "wmv": .video, "flv": .video, "ogv": .video,
        "x3f": .photo, "mka": .audio, "ogg": .audio, "oga": .audio, "opus": .audio, "wma": .audio, "ape": .audio, "wv": .audio,
    ]

    private static func classify(pathExtension: String) -> Classification? {
        guard let type = UTType(filenameExtension: pathExtension) else { return nil }
        let kind: MediaKind? = if type.conforms(to: .image) {
            .photo
        } else if type.conforms(to: .movie) {
            .video
        } else if type.conforms(to: .audio) {
            .audio
        } else {
            undeclaredKinds[pathExtension]
        }
        return kind.map { Classification(kind: $0, typeIdentifier: type.identifier) }
    }
}
