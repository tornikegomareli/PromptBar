#!/usr/bin/env swift

// Rasterises Design/icon.svg into Icon.icns.
//
// Uses AppKit's native SVG rasterisation so the repo needs no third-party
// tooling. Run via Scripts/make_icon.sh.

import AppKit
import Foundation

let fm = FileManager.default
let root = URL(fileURLWithPath: fm.currentDirectoryPath)
let svg = root.appendingPathComponent("Design/icon.svg")

guard let image = NSImage(contentsOf: svg) else {
    FileHandle.standardError.write(Data("error: could not load \(svg.path)\n".utf8))
    exit(1)
}

let iconset = root.appendingPathComponent("build/PromptBar.iconset")
try? fm.removeItem(at: iconset)
try fm.createDirectory(at: iconset, withIntermediateDirectories: true)

/// (points, scale) pairs Apple expects in an .iconset.
let variants: [(Int, Int)] = [
    (16, 1), (16, 2), (32, 1), (32, 2), (128, 1), (128, 2),
    (256, 1), (256, 2), (512, 1), (512, 2),
]

for (points, scale) in variants {
    let px = points * scale
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    ) else { continue }
    rep.size = NSSize(width: px, height: px)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    image.draw(
        in: NSRect(x: 0, y: 0, width: px, height: px),
        from: .zero, operation: .copy, fraction: 1
    )
    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else { continue }
    let suffix = scale == 1 ? "" : "@2x"
    let name = "icon_\(points)x\(points)\(suffix).png"
    try png.write(to: iconset.appendingPathComponent(name))
}

let convert = Process()
convert.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
convert.arguments = [
    "--convert", "icns",
    "--output", root.appendingPathComponent("Icon.icns").path,
    iconset.path,
]
try convert.run()
convert.waitUntilExit()
guard convert.terminationStatus == 0 else { exit(convert.terminationStatus) }

try? fm.removeItem(at: iconset)
print("Created Icon.icns from Design/icon.svg")
