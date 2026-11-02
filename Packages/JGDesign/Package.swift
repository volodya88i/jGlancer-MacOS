// swift-tools-version: 6.0
// jGlancer design system: tokens and SwiftUI components (docs/DESIGN.md).
import PackageDescription

let package = Package(
    name: "JGDesign",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "JGDesign", targets: ["JGDesign"]),
    ],
    targets: [
        .target(name: "JGDesign"),
        .testTarget(name: "JGDesignTests", dependencies: ["JGDesign"]),
    ],
    swiftLanguageModes: [.v6]
)
