import Foundation
import JGModel
import JGStore

/// Lists one directory for stage 1: media files with their file-system facts, and visible subdirectories.
///
/// Hidden items, packages (`.app`, `.photoslibrary`, …) and symbolic links are skipped.
public struct DirectoryLister: Sendable {
    static let keys: [URLResourceKey] = [
        .isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey,
        .contentModificationDateKey, .creationDateKey, .fileIdentifierKey,
    ]

    private let classifier: MediaClassifier

    public init(classifier: MediaClassifier = MediaClassifier()) {
        self.classifier = classifier
    }

    /// Lists `directory`, a folder inside root `rootID` at `relativePath`.
    public func list(_ directory: URL, rootID: Int64, relativePath: String, now: Date = Date()) throws -> DirectoryScan {
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: Self.keys, options: [.skipsHiddenFiles]
        )
        var files: [ScannedFile] = []
        var subdirectories: [String] = []
        files.reserveCapacity(entries.count)
        for entry in entries {
            guard let values = try? entry.resourceValues(forKeys: Set(Self.keys)), values.isSymbolicLink != true else { continue }
            let name = entry.lastPathComponent
            if values.isDirectory == true {
                if values.isPackage != true {
                    subdirectories.append(name)
                }
                continue
            }
            guard values.isRegularFile == true, let classification = classifier.classify(fileName: name) else { continue }
            files.append(ScannedFile(
                name: name,
                kind: classification.kind,
                typeIdentifier: classification.typeIdentifier,
                size: Int64(values.fileSize ?? 0),
                modifiedAt: values.contentModificationDate ?? .distantPast,
                createdAt: values.creationDate,
                inode: values.fileIdentifier
            ))
        }
        return DirectoryScan(
            rootID: rootID, relativePath: relativePath, files: files, subdirectories: subdirectories, scannedAt: now
        )
    }
}
