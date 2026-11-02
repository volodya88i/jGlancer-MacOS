#!/usr/bin/env -S swift -suppress-warnings
// Generates a large synthetic media library for benchmarks (docs/ARCHITECTURE.md §19–20).
//
// Usage: scripts/make_synthetic_library.swift N [--out DIR] [--photo-size small|12mp] [--per-folder K]
//   N             number of media files (e.g. 100000)
//   --out         output directory; default $TMPDIR/jGlancer-synthetic-N (outside the repo and Spotlight)
//   --photo-size  small = 640×480 seeds (default, fast scans); 12mp = 4000×3000 JPEG/HEIC seeds (thumbnail benchmarks)
//   --per-folder  files per event folder (default 250)
//
// Files are APFS clones of a few seed files: creation is fast and takes almost no disk space. They are spread over
// a year / month / event folder tree with deterministic names, kinds and modification dates.
// Mix: 80 % photos (JPEG 60, HEIC 15, PNG 5), 15 % video (MOV 10, MP4 5), 5 % audio (M4A 3, WAV 2).
// Video and audio seeds come from the fixtures of scripts/make_test_media.swift (generated first if missing).
// Clones share content, so content-hash identity checks are not meaningful on this library.
//
// Safety: writes only inside the output directory, which must not exist yet (or be empty). Never deletes anything.

import CoreGraphics
import Darwin
import Foundation
import ImageIO
import UniformTypeIdentifiers

struct ScriptError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) {
        self.description = description
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

// MARK: - Arguments

var arguments = Array(CommandLine.arguments.dropFirst())
guard let first = arguments.first, let count = Int(first), count > 0 else {
    fail("usage: make_synthetic_library.swift N [--out DIR] [--photo-size small|12mp] [--per-folder K]")
}

arguments.removeFirst()
var outputPath = (ProcessInfo.processInfo.environment["TMPDIR"] ?? NSTemporaryDirectory()) + "jGlancer-synthetic-\(count)"
var largePhotos = false
var perFolder = 250
while !arguments.isEmpty {
    let flag = arguments.removeFirst()
    guard let value = arguments.first else { fail("missing value for \(flag)") }
    arguments.removeFirst()
    switch flag {
    case "--out": outputPath = value
    case "--photo-size":
        guard ["small", "12mp"].contains(value) else { fail("--photo-size must be small or 12mp") }
        largePhotos = value == "12mp"
    case "--per-folder":
        guard let number = Int(value), number > 0 else { fail("--per-folder must be a positive number") }
        perFolder = number
    default: fail("unknown option \(flag)")
    }
}

let fileManager = FileManager.default
let output = URL(fileURLWithPath: outputPath).standardizedFileURL
let scriptDirectory = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let fixtures = scriptDirectory.appendingPathComponent("../TestMedia/generated/fixtures").standardizedFileURL

if fileManager.fileExists(atPath: output.path),
   let contents = try? fileManager.contentsOfDirectory(atPath: output.path), !contents.isEmpty
{
    fail("\(output.path) already exists and is not empty; choose another --out or delete it yourself")
}

// MARK: - Seeds

func makeJPEGLike(width: Int, height: Int, type: UTType) throws -> Data {
    guard let context = CGContext(
        data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
    ) else { throw ScriptError("cannot create bitmap context") }
    // Deterministic texture: gradient bands plus many small translucent rectangles, so the
    // encoded file has realistic entropy (and decode cost) rather than flat color.
    var state: UInt64 = 0x2545_F491_4F6C_DD1D
    func next() -> Double {
        state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
        return Double(state >> 11) / Double(1 << 53)
    }
    for band in 0 ..< 16 {
        context.setFillColor(CGColor(srgbRed: next(), green: next(), blue: next(), alpha: 1))
        context.fill(CGRect(x: 0, y: CGFloat(band * height / 16), width: CGFloat(width), height: CGFloat(height / 16 + 1)))
    }
    let side = Double(max(width, height)) / 80
    for _ in 0 ..< (width * height / 400) {
        context.setFillColor(CGColor(srgbRed: next(), green: next(), blue: next(), alpha: 0.35))
        context.fill(CGRect(x: next() * Double(width), y: next() * Double(height), width: side * next(), height: side * next()))
    }
    guard let image = context.makeImage() else { throw ScriptError("cannot render seed image") }
    let data = NSMutableData()
    guard let target = CGImageDestinationCreateWithData(data as CFMutableData, type.identifier as CFString, 1, nil) else {
        throw ScriptError("ImageIO cannot write \(type.identifier)")
    }
    // HEIC seeds embed a preview, as iPhones do; the thumbnail service uses it when big enough.
    let options: [CFString: Any] = [
        kCGImageDestinationLossyCompressionQuality: 0.9,
        kCGImageDestinationEmbedThumbnail: type == .heic,
    ]
    CGImageDestinationAddImage(target, image, options as CFDictionary)
    guard CGImageDestinationFinalize(target) else { throw ScriptError("encoding seed failed") }
    return data as Data
}

struct Kind {
    let share: Int // percent of files
    let seed: String
    let name: (Int) -> String
}

let kinds: [Kind] = [
    Kind(share: 60, seed: "photo.jpg") { String(format: "IMG_%06d.JPG", $0) },
    Kind(share: 15, seed: "photo.heic") { String(format: "IMG_%06d.HEIC", $0) },
    Kind(share: 5, seed: "photo.png") { String(format: "Screenshot %06d.png", $0) },
    Kind(share: 10, seed: "clip.mov") { String(format: "MOV_%06d.MOV", $0) },
    Kind(share: 5, seed: "clip.mp4") { String(format: "VID_%06d.mp4", $0) },
    Kind(share: 3, seed: "tone.m4a") { String(format: "Track %06d.m4a", $0) },
    Kind(share: 2, seed: "memo.wav") { String(format: "Memo %06d.wav", $0) },
]

func ensureFixtures() throws {
    let needed = ["clip.mov", "clip_with_audio.mp4", "tone_with_cover.m4a", "tone_440_mono.wav"]
    if needed.allSatisfy({ fileManager.fileExists(atPath: fixtures.appendingPathComponent($0).path) }) {
        return
    }
    print("Fixtures missing; running make_test_media.swift first…")
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
    process.arguments = ["swift", "-suppress-warnings", scriptDirectory.appendingPathComponent("make_test_media.swift").path]
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else { throw ScriptError("make_test_media.swift failed") }
}

/// Seeds live in a hidden folder inside the library, so the scanner skips them.
func writeSeeds(into seeds: URL) throws {
    try fileManager.createDirectory(at: seeds, withIntermediateDirectories: true)
    let (width, height) = largePhotos ? (4000, 3000) : (640, 480)
    try makeJPEGLike(width: width, height: height, type: .jpeg).write(to: seeds.appendingPathComponent("photo.jpg"))
    try makeJPEGLike(width: width, height: height, type: .heic).write(to: seeds.appendingPathComponent("photo.heic"))
    try makeJPEGLike(width: width / 2, height: height / 2, type: .png).write(to: seeds.appendingPathComponent("photo.png"))
    for (fixture, seed) in [
        ("clip.mov", "clip.mov"), ("clip_with_audio.mp4", "clip.mp4"),
        ("tone_with_cover.m4a", "tone.m4a"), ("tone_440_mono.wav", "memo.wav"),
    ] {
        try fileManager.copyItem(at: fixtures.appendingPathComponent(fixture), to: seeds.appendingPathComponent(seed))
    }
}

// MARK: - Library

/// Picks a kind for file `index` with the configured shares, deterministically.
func kind(for index: Int) -> Kind {
    var bucket = Int((UInt64(index) &* 2_654_435_761) % 100)
    for kind in kinds {
        if bucket < kind.share {
            return kind
        }
        bucket -= kind.share
    }
    return kinds[0]
}

/// `2021/2021-03 Event 0014`: six years of months, several events per month for big libraries.
func folderName(for folder: Int) -> String {
    let month = folder % 72
    let year = 2020 + month / 12
    return String(format: "%d/%d-%02d Event %04d", year, year, month % 12 + 1, folder)
}

func folderDate(for folder: Int) -> Date {
    let month = folder % 72
    var components = DateComponents()
    components.year = 2020 + month / 12
    components.month = month % 12 + 1
    components.day = 1 + folder / 72 % 28
    components.hour = 9
    return Calendar(identifier: .gregorian).date(from: components) ?? Date(timeIntervalSince1970: 0)
}

/// Clones `source` (APFS: shares blocks, no extra space); falls back to a copy. Returns whether it cloned.
func clone(_ source: URL, to target: URL) throws -> Bool {
    if clonefile(source.path, target.path, 0) == 0 {
        return true
    }
    try fileManager.copyItem(at: source, to: target) // not APFS
    return false
}

do {
    let start = Date()
    try ensureFixtures()
    try fileManager.createDirectory(at: output, withIntermediateDirectories: true)
    try Data("Generated by scripts/make_synthetic_library.swift. Safe to delete.\n".utf8)
        .write(to: output.appendingPathComponent(".jglancer-generated"))
    let seeds = output.appendingPathComponent(".seeds")
    try writeSeeds(into: seeds)

    var folders = 0
    var copies = 0
    var tally: [String: Int] = [:]
    for index in 0 ..< count {
        let folder = index / perFolder
        let directory = output.appendingPathComponent(folderName(for: folder), isDirectory: true)
        if index % perFolder == 0 {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
            folders += 1
        }
        let kind = kind(for: index)
        let target = directory.appendingPathComponent(kind.name(index))
        if try !clone(seeds.appendingPathComponent(kind.seed), to: target) {
            copies += 1
        }
        let modified = folderDate(for: folder).addingTimeInterval(Double(index % perFolder) * 600)
        try fileManager.setAttributes([.modificationDate: modified], ofItemAtPath: target.path)
        tally[kind.seed, default: 0] += 1
        if (index + 1) % max(1, count / 10) == 0 {
            print("  \(index + 1) / \(count)")
        }
    }
    let elapsed = Date().timeIntervalSince(start)
    print("Created \(count) files in \(folders) folders at \(output.path) in \(String(format: "%.1f", elapsed)) s")
    print("Mix: " + kinds.map { "\($0.seed) \(tally[$0.seed, default: 0])" }.joined(separator: ", "))
    print("Photo seeds: \(largePhotos ? "4000×3000" : "640×480"); APFS clones: \(count - copies), full copies: \(copies)")
} catch {
    fail("\(error)")
}
