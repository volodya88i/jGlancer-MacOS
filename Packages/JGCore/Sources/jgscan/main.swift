// jgscan — developer harness for the store and scanner (PLAN Phase 1). Not shipped in the app.
//
// Usage: swift run -c release jgscan <folder> [--db PATH] [--metadata] [--thumbnails N] [--list N] [--search TEXT]… [--watch]
// Reads files only. The database defaults to a fresh file in the temp directory.

import Darwin
import Foundation
import JGModel
import JGScanner
import JGStore
import JGThumbs

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

func milliseconds(_ seconds: TimeInterval) -> String {
    String(format: "%.1f ms", seconds * 1000)
}

func measure<T>(_ body: () async throws -> T) async rethrows -> (T, TimeInterval) {
    let start = Date()
    let value = try await body()
    return (value, Date().timeIntervalSince(start))
}

func fileSize(_ path: String) -> Int64 {
    ((try? FileManager.default.attributesOfItem(atPath: path))?[.size] as? NSNumber)?.int64Value ?? 0
}

func peakMemoryMB() -> Double {
    var usage = rusage()
    getrusage(RUSAGE_SELF, &usage)
    return Double(usage.ru_maxrss) / 1_048_576 // bytes on macOS
}

setvbuf(stdout, nil, _IOLBF, 0) // line-buffered, so --watch output can be piped or logged

var arguments = Array(CommandLine.arguments.dropFirst())
guard let folder = arguments.first, !folder.hasPrefix("--") else {
    fail("usage: jgscan <folder> [--db PATH] [--metadata] [--thumbnails N] [--list N] [--search TEXT]… [--watch]")
}

arguments.removeFirst()
var databasePath = NSTemporaryDirectory() + "jgscan-\(UUID().uuidString).sqlite"
var runMetadata = false
var thumbnailCount = 0
var listCount = 0
var watch = false
var searches: [String] = []
while let flag = arguments.first {
    arguments.removeFirst()
    switch flag {
    case "--db":
        guard !arguments.isEmpty else { fail("--db needs a path") }
        databasePath = arguments.removeFirst()
    case "--metadata": runMetadata = true
    case "--thumbnails": thumbnailCount = Int(arguments.isEmpty ? "" : arguments.removeFirst()) ?? 1000
    case "--watch": watch = true
    case "--search":
        guard !arguments.isEmpty else { fail("--search needs text") }
        searches.append(arguments.removeFirst())
    case "--list": listCount = Int(arguments.isEmpty ? "" : arguments.removeFirst()) ?? 20
    default: fail("unknown option \(flag)")
    }
}

do {
    print("database: \(databasePath)")
    let (store, openTime) = try await measure { try LibraryStore.open(at: URL(fileURLWithPath: databasePath)) }
    print("open + migrate: \(milliseconds(openTime))")
    let scanner = LibraryScanner(store: store)

    let existing = try await store.roots().first { $0.path == CanonicalPath.of(URL(fileURLWithPath: folder)) }
    let root: RootFolder
    if let existing {
        root = existing
        let (report, time) = try await measure { try await scanner.scan(rootID: existing.id) }
        print("rescan (stage 1): \(milliseconds(time)) — \(report)")
    } else {
        let ((added, report), time) = try await measure { try await scanner.addRoot(at: URL(fileURLWithPath: folder)) }
        root = added
        let rate = Double(report.added) / max(time, 0.001)
        print(String(format: "stage 1: %.2f s, %d directories, %d assets (%.0f files/s)", time, report.directories, report.added, rate))
        let (again, rescanTime) = try await measure { try await scanner.scan(rootID: root.id) }
        print("unchanged rescan: \(String(format: "%.2f s", rescanTime)), changes: \(again.hasChanges)")
    }

    var statistics = try await store.statistics()
    let kinds = statistics.assetsByKind.sorted { $0.key.rawValue < $1.key.rawValue }
        .map { "\($0.key) \($0.value)" }.joined(separator: ", ")
    print("assets: \(kinds); folders \(statistics.folders); missing \(statistics.missingAssets)")
    print("pending metadata: \(statistics.pendingMetadata)")

    if runMetadata {
        let (count, time) = try await measure { try await scanner.extractMetadata() }
        print(String(format: "stage 2: %.2f s for %d assets (%.0f/s)", time, count, Double(count) / max(time, 0.001)))
        statistics = try await store.statistics()
    }

    if thumbnailCount > 0 {
        try await benchmarkThumbnails(store: store, rootID: root.id, count: thumbnailCount)
    }

    let databaseBytes = fileSize(databasePath) + fileSize(databasePath + "-wal")
    let total = max(statistics.presentAssets, 1)
    print(String(format: "database: %.1f MB (%.0f bytes/asset)", Double(databaseBytes) / 1_048_576, Double(databaseBytes) / Double(total)))

    for query in [
        AssetQuery(scope: .library, sort: .name),
        AssetQuery(scope: .root(id: root.id), kinds: [.photo], sort: .dateModified, ascending: false),
        AssetQuery(scope: .library, sort: .dateCaptured),
    ] {
        let (refs, time) = try await measure { try await store.assetRefs(for: query) }
        print("refs \(query.scope) \(query.sort) kinds=\(query.kinds.count): \(refs.count) in \(milliseconds(time))")
    }
    let folders = try await store.folders(rootID: root.id)
    if let busiest = folders.last {
        let (refs, time) = try await measure {
            try await store.assetRefs(for: AssetQuery(scope: .folder(id: busiest.id, includeSubfolders: false)))
        }
        print("refs folder '\(busiest.relativePath)': \(refs.count) in \(milliseconds(time))")
    }

    for text in searches {
        // Library-wide, the slowest scope; the second run is the warm one the app sees while typing.
        let query = AssetQuery(scope: .library, search: text)
        _ = try await store.assetRefs(for: query)
        let (refs, time) = try await measure { try await store.assetRefs(for: query) }
        print("search '\(text)': \(refs.count) in \(milliseconds(time))")
    }

    if listCount > 0 {
        let refs = try await store.assetRefs(for: AssetQuery(scope: .root(id: root.id)))
        for asset in try await store.assets(ids: refs.prefix(listCount).map(\.id)) {
            let size = asset.width.map { "\($0)×\(asset.height ?? 0)" } ?? "-"
            let duration = asset.duration.map { String(format: "%.2fs", $0) } ?? ""
            let captured = asset.capturedAt.map { ISO8601DateFormatter().string(from: $0) } ?? ""
            let facts = [size, duration, asset.codec ?? "", captured, "[\(asset.metadataState)]"]
            print("  \(asset.kind)  \(asset.name)  \(asset.size) B  " + facts.joined(separator: "  "))
        }
    }
    print(String(format: "peak memory: %.0f MB", peakMemoryMB()))

    if watch {
        print("watching \(root.path) — Ctrl-C to stop")
        try await scanner.watch(rootID: root.id) { update in
            let paths = update.events.map { ($0.path as NSString).lastPathComponent }.prefix(5).joined(separator: ", ")
            let targets = update.targets.map { $0.relativePath.isEmpty ? "/" : $0.relativePath }
            let report = update.report
            print("events \(update.events.count) [\(paths)] → rescans \(targets)")
            print("  +\(report.added) ~\(report.updated) →\(report.moved) -\(report.missing) ↺\(report.revived)")
        }
    }
} catch {
    fail("\(error)")
}

/// Uncached thumbnail throughput (budget: ≥ 200/s for 12-MP JPEGs), then the same set served from cache.sqlite.
func benchmarkThumbnails(store: LibraryStore, rootID: Int64, count: Int) async throws {
    let cacheURL = URL(fileURLWithPath: NSTemporaryDirectory() + "jgscan-thumbs-\(UUID().uuidString).sqlite")
    let disk = try ThumbnailDiskCache.open(at: cacheURL)
    var groups: [(label: String, assets: [Asset])] = []
    for kind in MediaKind.allCases {
        let refs = try await store.assetRefs(for: AssetQuery(scope: .root(id: rootID), kinds: [kind]))
        let assets = try await store.assets(ids: refs.map(\.id))
        // Photos are measured per format: the budget is about 12-MP JPEGs.
        let byType = Dictionary(grouping: assets) { kind == .photo ? ($0.typeIdentifier ?? "?") : "\(kind)" }
        groups += byType.keys.sorted().map { ($0, Array(byType[$0, default: []].prefix(count))) }
    }
    for (label, assets) in groups {
        let requests = assets.map { asset in
            ThumbnailRequest(
                assetID: asset.id, url: asset.url, kind: asset.kind, typeIdentifier: asset.typeIdentifier,
                modifiedAt: asset.modifiedAt, duration: asset.duration, bucket: .medium
            )
        }
        for pass in ["uncached", "from cache.sqlite"] {
            let service = ThumbnailService(disk: disk)
            let (made, time) = await measure {
                await withTaskGroup(of: Bool.self) { group in
                    for request in requests {
                        group.addTask { await service.thumbnail(for: request, priority: .visible) != nil }
                    }
                    return await group.reduce(0) { $0 + ($1 ? 1 : 0) }
                }
            }
            let rate = Double(requests.count) / max(time, 0.001)
            print(String(
                format: "thumbnails %@ (%@, medium): %d in %.2f s = %.0f/s, %d with image",
                label,
                pass,
                requests.count,
                time,
                rate,
                made
            ))
        }
    }
    let used = try await disk.usedBytes()
    print(String(format: "cache.sqlite: %.1f MB", Double(used) / 1_048_576))
}
