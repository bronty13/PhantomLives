#!/usr/bin/env swift
//
// generate-icon.swift
//
// Renders the PurpleSpeak app icon — a purple speech bubble with a white
// sound-wave inside — into an .iconset directory. build-app.sh invokes this
// and then runs `iconutil -c icns` to produce AppIcon.icns. All drawing is
// CoreGraphics so the result is crisp at every size.

import AppKit
import CoreGraphics

func drawTile(side s: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(s), pixelsHigh: Int(s),
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high
    drawBackground(ctx: ctx, s: s)
    drawBubble(ctx: ctx, s: s)
    drawWave(ctx: ctx, s: s)
    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Rounded-rect purple gradient background (macOS squircle-ish).
func drawBackground(ctx: CGContext, s: CGFloat) {
    let inset = s * 0.05
    let bg = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = CGPath(roundedRect: bg, cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil)
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.80, green: 0.62, blue: 0.99, alpha: 1),
            CGColor(red: 0.40, green: 0.20, blue: 0.70, alpha: 1)
        ] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: bg.minX, y: bg.maxY),
                           end: CGPoint(x: bg.maxX, y: bg.minY), options: [])
    ctx.restoreGState()
}

/// A rounded speech bubble with a little tail at the bottom-left.
func drawBubble(ctx: CGContext, s: CGFloat) {
    let bubble = CGRect(x: s * 0.22, y: s * 0.30, width: s * 0.56, height: s * 0.42)
    let path = CGMutablePath()
    path.addRoundedRect(in: bubble, cornerWidth: s * 0.12, cornerHeight: s * 0.12)
    // Tail
    path.move(to: CGPoint(x: s * 0.34, y: s * 0.32))
    path.addLine(to: CGPoint(x: s * 0.27, y: s * 0.20))
    path.addLine(to: CGPoint(x: s * 0.45, y: s * 0.31))
    path.closeSubpath()
    ctx.addPath(path)
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.96))
    ctx.fillPath()
}

/// A 5-bar sound wave inside the bubble, in purple.
func drawWave(ctx: CGContext, s: CGFloat) {
    let purple = CGColor(red: 0.46, green: 0.24, blue: 0.78, alpha: 1)
    ctx.setFillColor(purple)
    let centerY = s * 0.51
    let barW = s * 0.045
    let gap = s * 0.045
    let heights: [CGFloat] = [0.10, 0.18, 0.26, 0.18, 0.10]
    let totalW = CGFloat(heights.count) * barW + CGFloat(heights.count - 1) * gap
    var x = s * 0.5 - totalW / 2
    for h in heights {
        let barH = s * h
        let r = CGRect(x: x, y: centerY - barH / 2, width: barW, height: barH)
        ctx.addPath(CGPath(roundedRect: r, cornerWidth: barW / 2, cornerHeight: barW / 2, transform: nil))
        ctx.fillPath()
        x += barW + gap
    }
}

let variants: [(Int, String)] = [
    (16, "icon_16x16.png"), (32, "icon_16x16@2x.png"),
    (32, "icon_32x32.png"), (64, "icon_32x32@2x.png"),
    (128, "icon_128x128.png"), (256, "icon_128x128@2x.png"),
    (256, "icon_256x256.png"), (512, "icon_256x256@2x.png"),
    (512, "icon_512x512.png"), (1024, "icon_512x512@2x.png"),
]

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: generate-icon.swift <out-iconset-dir>\n".utf8))
    exit(2)
}
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
for (sz, name) in variants {
    let rep = drawTile(side: CGFloat(sz))
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("failed to encode \(name)\n".utf8)); exit(1)
    }
    try data.write(to: outDir.appendingPathComponent(name))
}
print("wrote \(variants.count) icon variants to \(outDir.path)")
