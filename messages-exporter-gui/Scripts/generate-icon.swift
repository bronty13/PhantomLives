#!/usr/bin/env swift
//
// generate-icon.swift
//
// Renders the MessagesExporterGUI app icon — a chat bubble over a download
// arrow on a teal squircle — into an .iconset directory. build-app.sh
// invokes this once and runs `iconutil -c icns` to produce AppIcon.icns.
//
// All drawing is CoreGraphics so the result is identical at every size; no
// bitmap scaling. Everything lives off proportions of `s`, so the same code
// produces both 16×16 and 1024×1024.

import AppKit
import CoreGraphics

func drawTile(side s: CGFloat) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(s), pixelsHigh: Int(s),
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    )!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let ctx = NSGraphicsContext.current!.cgContext
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    ctx.interpolationQuality = .high

    drawBackground(ctx: ctx, s: s)
    drawChatBubble(ctx: ctx, s: s)
    drawDownArrow(ctx: ctx, s: s)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Rounded-rectangle teal/blue gradient background.
func drawBackground(ctx: CGContext, s: CGFloat) {
    let inset = s * 0.05
    let bg = CGRect(x: inset, y: inset, width: s - inset*2, height: s - inset*2)
    let path = CGPath(roundedRect: bg,
                      cornerWidth: s * 0.22, cornerHeight: s * 0.22,
                      transform: nil)
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.30, green: 0.78, blue: 0.92, alpha: 1),
            CGColor(red: 0.10, green: 0.42, blue: 0.70, alpha: 1)
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: bg.minX, y: bg.maxY),
        end:   CGPoint(x: bg.maxX, y: bg.minY),
        options: []
    )
    ctx.restoreGState()
}

/// White rounded chat bubble in the upper portion of the tile, with a
/// little tail pointing down-left. Origin = bottom-left.
func drawChatBubble(ctx: CGContext, s: CGFloat) {
    let bubble = CGRect(x: s * 0.20, y: s * 0.46,
                        width: s * 0.60, height: s * 0.36)
    let cornerR = s * 0.10
    let bubblePath = CGMutablePath()
    bubblePath.addRoundedRect(in: bubble,
                              cornerWidth: cornerR, cornerHeight: cornerR)

    // Tail: small triangle dangling off the lower-left of the bubble.
    let tail = CGMutablePath()
    tail.move(to: CGPoint(x: s * 0.32, y: s * 0.46))
    tail.addLine(to: CGPoint(x: s * 0.26, y: s * 0.36))
    tail.addLine(to: CGPoint(x: s * 0.42, y: s * 0.46))
    tail.closeSubpath()

    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.addPath(bubblePath)
    ctx.fillPath()
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.addPath(tail)
    ctx.fillPath()

    // Three subtle "message line" dots inside the bubble.
    let dotY = s * 0.62
    let dotR = s * 0.04
    let dotColor = CGColor(red: 0.10, green: 0.42, blue: 0.70, alpha: 0.85)
    ctx.setFillColor(dotColor)
    for cx in [s * 0.36, s * 0.50, s * 0.64] {
        ctx.fillEllipse(in: CGRect(x: cx - dotR, y: dotY - dotR,
                                   width: dotR * 2, height: dotR * 2))
    }
}

/// Down-pointing arrow under the bubble, signaling "export / save out".
/// White, with a subtle drop shadow against the gradient.
func drawDownArrow(ctx: CGContext, s: CGFloat) {
    ctx.saveGState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.30)
    shadow.shadowBlurRadius = s * 0.015
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.008)
    shadow.set()

    let cx = s * 0.50
    let shaftW = s * 0.10
    let shaftTop = s * 0.36
    let shaftBottom = s * 0.22
    let headTop = s * 0.22
    let headBottom = s * 0.10
    let headHalfW = s * 0.13

    let arrow = CGMutablePath()
    arrow.move(to: CGPoint(x: cx - shaftW/2, y: shaftTop))
    arrow.addLine(to: CGPoint(x: cx + shaftW/2, y: shaftTop))
    arrow.addLine(to: CGPoint(x: cx + shaftW/2, y: shaftBottom))
    arrow.addLine(to: CGPoint(x: cx + headHalfW, y: headTop))
    arrow.addLine(to: CGPoint(x: cx, y: headBottom))
    arrow.addLine(to: CGPoint(x: cx - headHalfW, y: headTop))
    arrow.addLine(to: CGPoint(x: cx - shaftW/2, y: shaftBottom))
    arrow.closeSubpath()

    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.addPath(arrow)
    ctx.fillPath()
    ctx.restoreGState()
}

let variants: [(Int, String)] = [
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

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: generate-icon.swift <out-iconset-dir>\n".utf8))
    exit(2)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for (sz, name) in variants {
    let rep = drawTile(side: CGFloat(sz))
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("failed to encode \(name)\n".utf8))
        exit(1)
    }
    let url = outDir.appendingPathComponent(name)
    try data.write(to: url)
    print("wrote \(url.path) (\(sz)×\(sz))")
}
