#!/usr/bin/env swift
import AppKit
import Foundation

let iconsetDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "/tmp/PurpleDiary.iconset"

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

    let radius   = s * 0.225
    let iconRect = NSRect(x: 0, y: 0, width: s, height: s)
    let roundRect = NSBezierPath(roundedRect: iconRect, xRadius: radius, yRadius: radius)

    // Background gradient — violet → deep purple (the PurpleDiary identity).
    ctx.saveGState()
    roundRect.addClip()
    let bgTop    = CGColor(red: 0.55, green: 0.40, blue: 1.00, alpha: 1)
    let bgBottom = CGColor(red: 0.30, green: 0.16, blue: 0.62, alpha: 1)
    let bgGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: [bgTop, bgBottom] as CFArray,
                             locations: [0.0, 1.0])!
    ctx.drawLinearGradient(bgGrad,
                            start: CGPoint(x: s * 0.15, y: s),
                            end:   CGPoint(x: s * 0.85, y: 0),
                            options: [])
    ctx.restoreGState()

    // A closed book / journal: rounded cover with a spine band and a bookmark.
    let bookW = s * 0.46
    let bookH = s * 0.58
    let bookX = (s - bookW) / 2
    let bookY = (s - bookH) / 2
    let bookRect = NSRect(x: bookX, y: bookY, width: bookW, height: bookH)
    let bookPath = NSBezierPath(roundedRect: bookRect, xRadius: s * 0.04, yRadius: s * 0.04)
    NSColor(white: 1, alpha: 0.95).setFill()
    bookPath.fill()

    // Spine band on the left edge of the cover.
    let spineW = bookW * 0.16
    let spineRect = NSRect(x: bookX, y: bookY, width: spineW, height: bookH)
    ctx.saveGState()
    NSBezierPath(roundedRect: bookRect, xRadius: s * 0.04, yRadius: s * 0.04).addClip()
    NSColor(calibratedRed: 0.62, green: 0.48, blue: 1.0, alpha: 1).setFill()
    NSBezierPath(rect: spineRect).fill()
    ctx.restoreGState()

    // Three "text" lines on the cover.
    let lineX = bookX + spineW + bookW * 0.10
    let lineW = bookW * 0.56
    let lineH = max(1.5, s * 0.018)
    NSColor(calibratedRed: 0.55, green: 0.42, blue: 0.95, alpha: 0.55).setFill()
    for i in 0..<3 {
        let y = bookY + bookH * 0.62 - CGFloat(i) * bookH * 0.14
        let r = NSRect(x: lineX, y: y, width: lineW * (i == 2 ? 0.6 : 1.0), height: lineH)
        NSBezierPath(roundedRect: r, xRadius: lineH / 2, yRadius: lineH / 2).fill()
    }

    // Bookmark ribbon hanging from the top.
    let ribbonW = bookW * 0.10
    let ribbonX = bookX + bookW * 0.70
    let ribbonTop = bookY + bookH
    let ribbonBottom = bookY + bookH * 0.18
    let notch = ribbonW * 0.5
    let ribbon = NSBezierPath()
    ribbon.move(to: NSPoint(x: ribbonX, y: ribbonTop))
    ribbon.line(to: NSPoint(x: ribbonX, y: ribbonBottom))
    ribbon.line(to: NSPoint(x: ribbonX + ribbonW / 2, y: ribbonBottom + notch))
    ribbon.line(to: NSPoint(x: ribbonX + ribbonW, y: ribbonBottom))
    ribbon.line(to: NSPoint(x: ribbonX + ribbonW, y: ribbonTop))
    ribbon.close()
    NSColor(calibratedRed: 1.0, green: 0.62, blue: 0.30, alpha: 1).setFill()
    ribbon.fill()

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
        print("  ✗ failed to create context for \(pixels)px")
        continue
    }
    drawIcon(into: ctx, pixels: pixels)
    guard let cgImg = ctx.makeImage() else { continue }
    let rep = NSBitmapImageRep(cgImage: cgImg)
    let dest = URL(fileURLWithPath: iconsetDir).appendingPathComponent(filename)
    if let png = rep.representation(using: .png, properties: [:]) {
        try? png.write(to: dest)
        print("  wrote \(pixels)px → \(filename)")
    }
}
print("✓ Icon set generated at \(iconsetDir)")
