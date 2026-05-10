#!/usr/bin/env swift
import AppKit

// Renders the PurpleLife app icon into the iconset directory passed as the
// first argument. Produces every macOS-required size in both 1x and 2x.
// Stand-in until a hand-designed icon is added; family-consistent with
// PurpleTracker's "PT°" treatment but with a vertical purple gradient and a
// trailing dot accent ("PL•") to signal a richer object model.

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write("Usage: generate-icon.swift <iconset-dir>\n".data(using: .utf8)!)
    exit(2)
}
let iconsetDir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let sizes: [(label: String, px: Int)] = [
    ("16x16",      16),  ("16x16@2x",   32),
    ("32x32",      32),  ("32x32@2x",   64),
    ("128x128",   128),  ("128x128@2x", 256),
    ("256x256",   256),  ("256x256@2x", 512),
    ("512x512",   512),  ("512x512@2x", 1024),
]

let purpleTop    = NSColor(srgbRed: 0.611, green: 0.435, blue: 0.812, alpha: 1)
let purpleBottom = NSColor(srgbRed: 0.388, green: 0.227, blue: 0.612, alpha: 1)
let white        = NSColor.white

for (label, px) in sizes {
    // Render into a fixed-pixel bitmap rep (not via NSImage.lockFocus +
    // tiffRepresentation, which on a Retina display returns 2x-scaled
    // bitmaps and trips Xcode's icon-size warnings).
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 32
    ) else {
        FileHandle.standardError.write("Failed to allocate rep \(label)\n".data(using: .utf8)!)
        exit(1)
    }
    rep.size = NSSize(width: px, height: px)

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)

    let r = NSRect(x: 0, y: 0, width: px, height: px)
    let radius = CGFloat(px) * 0.22
    let path = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
    path.addClip()

    // Vertical gradient background.
    let gradient = NSGradient(starting: purpleTop, ending: purpleBottom)
    gradient?.draw(in: r, angle: -90)

    // "PL" letters, heavy.
    let text = "PL" as NSString
    let fontSize = CGFloat(px) * 0.46
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
        .foregroundColor: white,
    ]
    let textSize = text.size(withAttributes: attrs)
    // Shift left a hair so the trailing dot reads as part of the lockup.
    let dotRadius = CGFloat(px) * 0.055
    let dotGap    = CGFloat(px) * 0.025
    let lockupWidth = textSize.width + dotGap + dotRadius * 2
    let textOrigin = NSPoint(
        x: (CGFloat(px) - lockupWidth) / 2,
        y: (CGFloat(px) - textSize.height) / 2
    )
    text.draw(at: textOrigin, withAttributes: attrs)

    // Trailing dot accent — sits on the baseline at the right end of the lockup.
    let dotCenterX = textOrigin.x + textSize.width + dotGap + dotRadius
    let dotCenterY = textOrigin.y + textSize.height * 0.18
    let dotRect = NSRect(
        x: dotCenterX - dotRadius,
        y: dotCenterY - dotRadius,
        width: dotRadius * 2,
        height: dotRadius * 2
    )
    white.setFill()
    NSBezierPath(ovalIn: dotRect).fill()

    NSGraphicsContext.restoreGraphicsState()

    guard let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("Failed to encode \(label)\n".data(using: .utf8)!)
        exit(1)
    }
    let outURL = URL(fileURLWithPath: iconsetDir).appendingPathComponent("icon_\(label).png")
    try png.write(to: outURL)
}
