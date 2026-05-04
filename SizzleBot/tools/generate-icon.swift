#!/usr/bin/env swift
//
//  generate-icon.swift
//
//  Renders the SizzleBot app icon at every size required by the macOS app
//  icon set. Design: a 🌶️ emoji centered on a vertical purple → pink
//  gradient with the standard macOS rounded-square mask.
//
//  Usage:
//      swift tools/generate-icon.swift Sources/SizzleBot/Assets.xcassets/AppIcon.appiconset
//
//  Re-run any time the design changes; Xcode will pick up the new PNGs on
//  next build.
//

import Cocoa

// Each entry produces one PNG at the given pixel size with the given filename.
// The macOS app icon set requires 10 PNGs covering all (size, scale)
// combinations from 16pt @1x through 512pt @2x.
struct IconSize {
    let pixels: Int
    let filename: String
}

let outputs: [IconSize] = [
    IconSize(pixels: 16,   filename: "icon_16x16.png"),
    IconSize(pixels: 32,   filename: "icon_16x16@2x.png"),
    IconSize(pixels: 32,   filename: "icon_32x32.png"),
    IconSize(pixels: 64,   filename: "icon_32x32@2x.png"),
    IconSize(pixels: 128,  filename: "icon_128x128.png"),
    IconSize(pixels: 256,  filename: "icon_128x128@2x.png"),
    IconSize(pixels: 256,  filename: "icon_256x256.png"),
    IconSize(pixels: 512,  filename: "icon_256x256@2x.png"),
    IconSize(pixels: 512,  filename: "icon_512x512.png"),
    IconSize(pixels: 1024, filename: "icon_512x512@2x.png"),
]

// Brand gradient: deep purple at the top, hot pink at the bottom.
let topColor    = NSColor(red: 0.62, green: 0.20, blue: 0.94, alpha: 1.0)
let bottomColor = NSColor(red: 0.96, green: 0.32, blue: 0.62, alpha: 1.0)

// macOS app icons use a "squircle"-ish rounded rectangle. Apple's reference
// shape has corner radius ~22.37% of the side length; close enough.
let cornerRadiusFraction: CGFloat = 0.2237

// Glyph: chili pepper, matching the "Sizzle" name.
let glyph = "🌶️"

// Glyph occupies ~62% of the icon side length — leaves a comfortable margin
// at the smallest sizes while still reading clearly at 1024px.
let glyphFraction: CGFloat = 0.62

func renderIcon(pixels: Int) -> Data? {
    let side = CGFloat(pixels)

    // Draw straight into a bitmap rep — `NSImage.lockFocus` doesn't behave
    // reliably from a CLI context (no NSApplication).
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: pixels,
        pixelsHigh: pixels,
        bitsPerSample: 8,
        samplesPerPixel: 4,
        hasAlpha: true,
        isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0,
        bitsPerPixel: 0
    ) else { return nil }
    rep.size = NSSize(width: side, height: side)

    NSGraphicsContext.saveGraphicsState()
    defer { NSGraphicsContext.restoreGraphicsState() }
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    NSGraphicsContext.current?.imageInterpolation = .high
    NSGraphicsContext.current?.shouldAntialias = true

    let bounds = NSRect(x: 0, y: 0, width: side, height: side)
    let radius = side * cornerRadiusFraction
    let clipPath = NSBezierPath(roundedRect: bounds, xRadius: radius, yRadius: radius)
    clipPath.addClip()

    if let gradient = NSGradient(colors: [topColor, bottomColor]) {
        gradient.draw(in: clipPath, angle: -90)
    }

    // Draw the emoji. Apple Color Emoji is a colored bitmap font, so any
    // foreground colour is ignored — it renders in its native colours,
    // which is exactly what we want.
    let fontSize = side * glyphFraction
    let font = NSFont.systemFont(ofSize: fontSize)
    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center

    let attributes: [NSAttributedString.Key: Any] = [
        .font: font,
        .paragraphStyle: paragraph,
    ]
    let attributed = NSAttributedString(string: glyph, attributes: attributes)

    let measured = attributed.boundingRect(
        with: NSSize(width: side, height: side),
        options: [.usesLineFragmentOrigin, .usesFontLeading]
    )
    let drawX = (side - measured.width) / 2.0
    // Slight vertical fudge to optically center the chili — the bounding
    // box doesn't quite match what the eye reads as "centered."
    let drawY = (side - measured.height) / 2.0 - measured.height * 0.04
    let drawRect = NSRect(x: drawX, y: drawY, width: measured.width, height: measured.height)
    attributed.draw(in: drawRect)

    return rep.representation(using: .png, properties: [:])
}

guard CommandLine.arguments.count >= 2 else {
    print("usage: generate-icon.swift <output-dir-AppIcon.appiconset>")
    exit(2)
}

let outputDirString = CommandLine.arguments[1]
let outputDir = URL(fileURLWithPath: outputDirString)
try? FileManager.default.createDirectory(at: outputDir, withIntermediateDirectories: true)

for entry in outputs {
    guard let png = renderIcon(pixels: entry.pixels) else {
        FileHandle.standardError.write("failed: \(entry.filename)\n".data(using: .utf8)!)
        exit(1)
    }
    let url = outputDir.appendingPathComponent(entry.filename)
    do {
        try png.write(to: url)
        print("wrote \(entry.filename) (\(entry.pixels)×\(entry.pixels))")
    } catch {
        FileHandle.standardError.write("write failed for \(entry.filename): \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

print("done — \(outputs.count) PNGs in \(outputDir.path)")
