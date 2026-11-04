#!/usr/bin/env swift
// Fills the app icon set from scripts/icon/jGlancer.icns, the glass icon as its designer exported it (DECISIONS
// D-105), unchanged. The design's source is scripts/icon/jglancer-glass-dark.svg; the .icns keeps its film grain,
// which WebKit cannot render.
//
// Usage: swift scripts/make_app_icon.swift [path/to/AppIcon.appiconset]

import Foundation

let scripts = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : scripts.appendingPathComponent("../App/Resources/Assets.xcassets/AppIcon.appiconset").standardizedFileURL
let files = FileManager.default
let iconset = files.temporaryDirectory.appendingPathComponent("jGlancer-\(UUID().uuidString).iconset")

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "iconset", scripts.appendingPathComponent("icon/jGlancer.icns").path, "-o", iconset.path]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else { fatalError("iconutil failed") }

/// The names iconutil writes are the ones the asset catalog lists.
let names = try files.contentsOfDirectory(atPath: iconset.path).filter { $0.hasSuffix(".png") }.sorted()
for name in names {
    let target = output.appendingPathComponent(name)
    try? files.removeItem(at: target)
    try files.copyItem(at: iconset.appendingPathComponent(name), to: target)
}

try? files.removeItem(at: iconset)
print("Wrote \(names.count) icons to \(output.path)")
