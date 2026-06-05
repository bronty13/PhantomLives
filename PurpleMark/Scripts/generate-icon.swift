#!/usr/bin/env swift
import AppKit
import Foundation

// Generates PurpleMark's AppIcon.iconset: a purple rounded-rect tile with the
// canonical Markdown mark — a bold "M" followed by a downward arrow "↓".

let iconsetDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "/tmp/PurpleMark.iconset"

try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let sizes: [(Int, String)] = [
    (16,   "icon_16x16.png"),
    (32,   "icon_16x16@2x.png"),
    (32,   "icon_32x32.png"),
    (64,   "icon_32x32@2x.png"),
    (128,  "icon_128x128.png"),
    (256,  "icon_128x128@2x.png"),
    (256,  "icon_256x256.png"),
    (512,  "icon_256x256@2x.png"),
    (512,  "icon_512x512.png"),
    (1024, "icon_512x512@2x.png"),
]

func drawIcon(into ctx: CGContext, pixels: Int) {
    let s = CGFloat(pixels)
    let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx

    let radius = s * 0.225
    let iconRect = NSRect(x: 0, y: 0, width: s, height: s)
    let roundRect = NSBezierPath(roundedRect: iconRect, xRadius: radius, yRadius: radius)

    // Purple gradient background.
    ctx.saveGState()
    roundRect.addClip()
    let bgTop    = CGColor(red: 0.55, green: 0.36, blue: 0.96, alpha: 1)   // light violet
    let bgBottom = CGColor(red: 0.34, green: 0.16, blue: 0.74, alpha: 1)   // deep purple
    let bgGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                            colors: [bgTop, bgBottom] as CFArray,
                            locations: [0.0, 1.0])!
    ctx.drawLinearGradient(bgGrad,
                           start: CGPoint(x: s * 0.15, y: s),
                           end:   CGPoint(x: s * 0.85, y: 0),
                           options: [])
    ctx.restoreGState()

    // The Markdown "M↓" mark, drawn with strokes so it scales crisply.
    let ink = NSColor.white
    ink.setStroke()
    ink.setFill()

    let lw = max(1.5, s * 0.075)
    let path = NSBezierPath()
    path.lineWidth = lw
    path.lineCapStyle = .round
    path.lineJoinStyle = .round

    // "M" — left third of the tile.
    let mTop = s * 0.66
    let mBot = s * 0.34
    let mLeft = s * 0.16
    let mMidX = s * 0.345
    let mRight = s * 0.53
    path.move(to: CGPoint(x: mLeft, y: mBot))
    path.line(to: CGPoint(x: mLeft, y: mTop))
    path.line(to: CGPoint(x: mMidX, y: s * 0.46))
    path.line(to: CGPoint(x: mRight, y: mTop))
    path.line(to: CGPoint(x: mRight, y: mBot))
    path.stroke()

    // "↓" — right side: a vertical stem with an arrowhead.
    let aX = s * 0.72
    let aTop = s * 0.66
    let aBot = s * 0.345
    let stem = NSBezierPath()
    stem.lineWidth = lw
    stem.lineCapStyle = .round
    stem.lineJoinStyle = .round
    stem.move(to: CGPoint(x: aX, y: aTop))
    stem.line(to: CGPoint(x: aX, y: aBot))
    stem.stroke()
    // Arrowhead (filled triangle).
    let head = NSBezierPath()
    let hw = s * 0.085
    let hh = s * 0.11
    head.move(to: CGPoint(x: aX - hw, y: aBot + hh * 0.55))
    head.line(to: CGPoint(x: aX + hw, y: aBot + hh * 0.55))
    head.line(to: CGPoint(x: aX, y: aBot - hh * 0.45))
    head.close()
    head.fill()

    // Top sheen.
    ctx.saveGState()
    roundRect.addClip()
    let hlColors = [CGColor(gray: 1, alpha: 0.20), CGColor(gray: 1, alpha: 0)]
    let hlGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                            colors: hlColors as CFArray, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(hlGrad,
                           start: CGPoint(x: s * 0.5, y: s),
                           end:   CGPoint(x: s * 0.5, y: s * 0.72),
                           options: [])
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
}

for (pixels, filename) in sizes {
    let space = CGColorSpaceCreateDeviceRGB()
    guard let ctx = CGContext(data: nil, width: pixels, height: pixels,
                              bitsPerComponent: 8, bytesPerRow: 0, space: space,
                              bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        continue
    }
    drawIcon(into: ctx, pixels: pixels)
    guard let cgImg = ctx.makeImage() else { continue }
    let rep = NSBitmapImageRep(cgImage: cgImg)
    let dest = URL(fileURLWithPath: iconsetDir).appendingPathComponent(filename)
    if let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: dest)
    }
}
print("✓ Icon set generated at \(iconsetDir)")
