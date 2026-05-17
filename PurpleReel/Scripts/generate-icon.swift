#!/usr/bin/env swift
import AppKit

// Generates the PurpleReel app icon: a stylized film reel (outer ring +
// inner hub + sprocket holes) on a deep-purple rounded square. Drawn
// programmatically so it renders crisply at every required macOS icon
// size without external assets.
//
// Usage: generate-icon.swift <iconset-dir>

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

let purpleDark  = NSColor(srgbRed: 0.290, green: 0.165, blue: 0.490, alpha: 1)
let purpleLight = NSColor(srgbRed: 0.580, green: 0.396, blue: 0.812, alpha: 1)
let reelBody    = NSColor(srgbRed: 0.18,  green: 0.10,  blue: 0.32,  alpha: 1)
let highlight   = NSColor(white: 1.0, alpha: 0.12)
let hubColor    = NSColor(srgbRed: 0.62,  green: 0.44,  blue: 0.86,  alpha: 1)

func render(px: Int) -> NSBitmapImageRep {
    // Build a bitmap rep at exact pixel dimensions and render into a
    // graphics context targeting it. NSImage.lockFocus() would use the
    // current display's backing scale (2x on retina) and produce a
    // double-sized PNG, which the asset compiler rejects.
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 32
    ) else { fatalError("could not allocate bitmap rep at \(px)px") }
    rep.size = NSSize(width: px, height: px)
    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    defer {
        NSGraphicsContext.restoreGraphicsState()
    }

    let f = CGFloat(px)
    let rect = NSRect(x: 0, y: 0, width: f, height: f)
    let radius = f * 0.22

    // Background: vertical purple gradient inside rounded-rect.
    let bgPath = NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
    bgPath.addClip()
    let gradient = NSGradient(starting: purpleLight, ending: purpleDark)!
    gradient.draw(in: rect, angle: -90)

    // Soft top highlight band for depth.
    let topBand = NSBezierPath(rect: NSRect(x: 0, y: f * 0.55, width: f, height: f * 0.45))
    highlight.setFill()
    topBand.fill()

    // Reel: centered circle. Outer ring is the dark "body" of the reel.
    let reelDiameter = f * 0.78
    let reelOrigin = NSPoint(x: (f - reelDiameter) / 2, y: (f - reelDiameter) / 2)
    let reelRect = NSRect(origin: reelOrigin, size: NSSize(width: reelDiameter, height: reelDiameter))
    let reelPath = NSBezierPath(ovalIn: reelRect)
    reelBody.setFill()
    reelPath.fill()

    // Subtle outer rim highlight.
    let rimPath = NSBezierPath(ovalIn: reelRect)
    rimPath.lineWidth = max(1, f * 0.012)
    NSColor(white: 1.0, alpha: 0.25).setStroke()
    rimPath.stroke()

    // Sprocket holes (4 around the hub) — these read as "film reel"
    // even at 16×16 because they break the solid disk silhouette.
    let holeCount = 4
    let holeRing = reelDiameter * 0.30  // distance from center to hole-center
    let holeRadius = reelDiameter * 0.14
    let cx = f / 2
    let cy = f / 2
    for i in 0..<holeCount {
        let angle = (.pi / 2) + (CGFloat.pi * 2 * CGFloat(i)) / CGFloat(holeCount)
        let hx = cx + cos(angle) * holeRing
        let hy = cy + sin(angle) * holeRing
        let holeRect = NSRect(x: hx - holeRadius, y: hy - holeRadius,
                              width: holeRadius * 2, height: holeRadius * 2)
        let holePath = NSBezierPath(ovalIn: holeRect)
        // Hole color matches background-ish to read as cut-through.
        purpleDark.setFill()
        holePath.fill()
    }

    // Central hub — small accent circle.
    let hubDiameter = reelDiameter * 0.20
    let hubRect = NSRect(x: cx - hubDiameter / 2, y: cy - hubDiameter / 2,
                          width: hubDiameter, height: hubDiameter)
    let hubPath = NSBezierPath(ovalIn: hubRect)
    hubColor.setFill()
    hubPath.fill()

    return rep
}

for (label, px) in sizes {
    let rep = render(px: px)
    guard let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("Failed to render \(label)\n".data(using: .utf8)!)
        exit(1)
    }
    let outURL = URL(fileURLWithPath: iconsetDir).appendingPathComponent("icon_\(label).png")
    try png.write(to: outURL)
}
