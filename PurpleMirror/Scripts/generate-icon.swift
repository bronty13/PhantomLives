#!/usr/bin/env swift
//
// generate-icon.swift — renders the PurpleMirror app icon into an .iconset
// directory. build-app.sh invokes this and then runs `iconutil -c icns` to
// produce AppIcon.icns. All drawing is proportional to the tile side `s`, so
// the same code yields crisp output at every size (no bitmap scaling).
//
// Design: a purple squircle (the PhantomLives "Purple*" family look) with a
// white circular two-arrow "sync/mirror" glyph centered on it.

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
    drawSyncGlyph(ctx: ctx, s: s)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Rounded-rectangle purple gradient background (macOS squircle-ish).
func drawBackground(ctx: CGContext, s: CGFloat) {
    let inset = s * 0.05
    let bg = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = CGPath(roundedRect: bg, cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil)
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.78, green: 0.60, blue: 0.98, alpha: 1),
            CGColor(red: 0.42, green: 0.22, blue: 0.72, alpha: 1)
        ] as CFArray,
        locations: [0, 1])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: bg.minX, y: bg.maxY),
                           end: CGPoint(x: bg.maxX, y: bg.minY),
                           options: [])
    ctx.restoreGState()
}

/// Two white arcs forming a clockwise "sync" ring, each capped with a filled
/// arrowhead — the classic refresh/mirror motif. Drawn purely with CG so it is
/// self-contained and identical at every size.
func drawSyncGlyph(ctx: CGContext, s: CGFloat) {
    let c = CGPoint(x: s / 2, y: s / 2)
    let r = s * 0.255
    let lw = s * 0.085
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.setLineWidth(lw)
    ctx.setLineCap(.round)

    // Two arcs, 180° apart. Each sweeps ~150°, leaving a gap where the other's
    // arrowhead sits.
    for base in [CGFloat(0), CGFloat.pi] {
        let start = base + (20 * .pi / 180)
        let end   = base + (170 * .pi / 180)
        ctx.beginPath()
        ctx.addArc(center: c, radius: r, startAngle: start, endAngle: end, clockwise: false)
        ctx.strokePath()

        // Arrowhead at `start`, pointing clockwise (tangent = start - 90°).
        let tip = CGPoint(x: c.x + cos(start) * r, y: c.y + sin(start) * r)
        let tangent = start - (.pi / 2)           // clockwise direction
        let ah = lw * 1.9                          // arrowhead half-length
        let aw = lw * 1.5                          // arrowhead half-width
        let dirX = cos(tangent), dirY = sin(tangent)
        let perpX = cos(tangent + .pi / 2), perpY = sin(tangent + .pi / 2)
        let p1 = CGPoint(x: tip.x + dirX * ah, y: tip.y + dirY * ah)               // forward point
        let p2 = CGPoint(x: tip.x - dirX * ah + perpX * aw, y: tip.y - dirY * ah + perpY * aw)
        let p3 = CGPoint(x: tip.x - dirX * ah - perpX * aw, y: tip.y - dirY * ah - perpY * aw)
        ctx.beginPath()
        ctx.move(to: p1); ctx.addLine(to: p2); ctx.addLine(to: p3); ctx.closePath()
        ctx.fillPath()
    }
}

// MARK: - Emit the iconset

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

let variants: [(name: String, px: CGFloat)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
]

for v in variants {
    let rep = drawTile(side: v.px)
    guard let data = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("failed to encode \(v.name)\n".data(using: .utf8)!)
        exit(1)
    }
    let path = (outDir as NSString).appendingPathComponent(v.name)
    try? data.write(to: URL(fileURLWithPath: path))
}
print("Wrote \(variants.count) icon variants to \(outDir)")
