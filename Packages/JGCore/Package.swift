// swift-tools-version: 6.0
// UI-free core of jGlancer. Module graph and rules: docs/ARCHITECTURE.md §3.
// JGCore never imports SwiftUI or AppKit.
import PackageDescription

let grdb: Target.Dependency = .product(name: "GRDB", package: "GRDB.swift")

let package = Package(
    name: "JGCore",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "JGModel", targets: ["JGModel"]),
        .library(name: "JGStore", targets: ["JGStore"]),
        .library(name: "JGScanner", targets: ["JGScanner"]),
        .library(name: "JGThumbs", targets: ["JGThumbs"]),
        .library(name: "JGPlayback", targets: ["JGPlayback"]),
        .library(name: "JGMatroska", targets: ["JGMatroska"]),
        .library(name: "JGActions", targets: ["JGActions"]),
        .library(name: "JGSettings", targets: ["JGSettings"]),
        .library(name: "JGStems", targets: ["JGStems"]),
        // Developer harness for the store and scanner; not part of the app.
        .executable(name: "jgscan", targets: ["jgscan"]),
    ],
    dependencies: [
        // The only pre-approved third-party dependency (CLAUDE.md). Latest stable 7.x.
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
    ],
    targets: [
        .target(name: "JGModel"),
        .target(name: "JGStore", dependencies: ["JGModel", grdb]),
        .target(name: "JGScanner", dependencies: ["JGModel", "JGStore", "JGMatroska"]),
        .target(name: "JGThumbs", dependencies: ["JGModel", "JGStore", "JGMatroska", grdb]),
        .target(name: "JGPlayback", dependencies: ["JGModel", "JGMatroska"]),
        .target(name: "JGMatroska"),
        .target(name: "JGActions", dependencies: ["JGModel", "JGStore", "JGScanner"]),
        .target(name: "JGSettings", dependencies: ["JGModel"]),
        // Split into Stems: Demucs through Core ML (D-97).
        .target(name: "JGStems"),
        .executableTarget(name: "jgscan", dependencies: ["JGModel", "JGStore", "JGScanner", "JGThumbs"]),

        // Shared helpers for test targets: temporary folders, generated media, polling.
        .target(name: "JGTestSupport", path: "Tests/JGTestSupport"),

        .testTarget(name: "JGModelTests", dependencies: ["JGModel"]),
        .testTarget(name: "JGStoreTests", dependencies: ["JGStore", "JGModel", "JGTestSupport", grdb]),
        .testTarget(name: "JGScannerTests", dependencies: ["JGScanner", "JGStore", "JGModel", "JGTestSupport"]),
        .testTarget(name: "JGThumbsTests", dependencies: ["JGThumbs", "JGModel", "JGTestSupport", grdb]),
        .testTarget(name: "JGPlaybackTests", dependencies: ["JGPlayback", "JGModel", "JGMatroska", "JGTestSupport"]),
        .testTarget(name: "JGMatroskaTests", dependencies: ["JGMatroska", "JGTestSupport"]),
        .testTarget(name: "JGActionsTests", dependencies: ["JGActions", "JGModel", "JGStore", "JGScanner", "JGTestSupport", grdb]),
        .testTarget(name: "JGSettingsTests", dependencies: ["JGSettings", "JGModel"]),
        .testTarget(name: "JGStemsTests", dependencies: ["JGStems", "JGTestSupport"]),
    ],
    swiftLanguageModes: [.v6]
)
