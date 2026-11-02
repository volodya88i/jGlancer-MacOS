#!/usr/bin/env swift
// Draws the app icon (the wave on a dark tile, DECISIONS D-101) from scripts/icon/jGlancer.svg and, below 40 px,
// jGlancer-small.svg, the same sources as the Windows app. They use blurs and blend modes, so WebKit renders them.
// The tile sits in the standard macOS icon grid: 824 of 1024, centered, with a soft shadow.
//
// Usage: swift scripts/make_app_icon.swift [path/to/AppIcon.appiconset]

import AppKit
import WebKit

let scripts = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
let output = CommandLine.arguments.count > 1
    ? URL(fileURLWithPath: CommandLine.arguments[1])
    : scripts.appendingPathComponent("../App/Resources/Assets.xcassets/AppIcon.appiconset").standardizedFileURL

/// Pixel size and file name of every icon the catalog lists.
let icons: [(pixels: Int, name: String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"), (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"), (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]

@MainActor
func render(_ svg: URL, done: @escaping (CGImage) -> Void) {
    let configuration = WKWebViewConfiguration()
    let web = WKWebView(frame: NSRect(x: 0, y: 0, width: 1024, height: 1024), configuration: configuration)
    web.setValue(false, forKey: "drawsBackground")
    let window = NSWindow(contentRect: web.frame, styleMask: .borderless, backing: .buffered, defer: false)
    window.contentView = web
    let markup = (try? String(contentsOf: svg, encoding: .utf8)) ?? ""
    web.loadHTMLString(
        "<!doctype html><html style='margin:0;background:transparent'><body style='margin:0'>\(markup)</body></html>",
        baseURL: nil
    )
    func snapshot() {
        let settings = WKSnapshotConfiguration()
        settings.rect = web.bounds
        settings.snapshotWidth = 1024
        web.takeSnapshot(with: settings) { image, _ in
            guard let image, let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { fatalError("no snapshot") }
            _ = window
            done(cg)
        }
    }
    DispatchQueue.main.asyncAfter(deadline: .now() + 2) { snapshot() }
}

func write(_ tile: CGImage, pixels: Int, to url: URL) {
    let size = CGFloat(pixels)
    guard let space = CGColorSpace(name: CGColorSpace.sRGB), let context = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
        space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { fatalError("no context") }
    context.interpolationQuality = .high
    let side = size * 824 / 1024
    let rect = CGRect(x: (size - side) / 2, y: (size - side) / 2 + size * 8 / 1024, width: side, height: side)
    context.setShadow(offset: CGSize(width: 0, height: -size * 10 / 1024), blur: size * 20 / 1024, color: CGColor(gray: 0, alpha: 0.35))
    context.draw(tile, in: rect)
    guard let image = context.makeImage(), let data = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]),
          (try? data.write(to: url)) != nil
    else { fatalError("no png") }
}

let app = NSApplication.shared
app.setActivationPolicy(.prohibited)
MainActor.assumeIsolated {
    render(scripts.appendingPathComponent("icon/jGlancer.svg")) { large in
        render(scripts.appendingPathComponent("icon/jGlancer-small.svg")) { small in
            for icon in icons {
                write(icon.pixels < 40 ? small : large, pixels: icon.pixels, to: output.appendingPathComponent(icon.name))
            }
            print("Wrote \(icons.count) icons to \(output.path)")
            exit(0)
        }
    }
}

app.run()
