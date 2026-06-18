#!/usr/bin/env swift
//
// generate-icon.swift
//
// Renders the Ircle app icon — a classic Mac OS "Platinum" window with a
// pinstriped title bar, a close box, and a bold blue channel "#" in the body —
// into an .iconset directory. build-app.sh invokes this once and then runs
// `iconutil -c icns` to produce AppIcon.icns.
//
// All drawing is CoreGraphics off proportions of `s`, so the same code renders
// crisp at 16×16 and 1024×1024 — no bitmap scaling, no binary asset. This is
// the deterministic, multi-machine-friendly icon source (see
// docs/app-icon-standard.md).

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
    drawWindow(ctx: ctx, s: s)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Rounded-rect Platinum grey gradient background.
func drawBackground(ctx: CGContext, s: CGFloat) {
    let inset = s * 0.05
    let bg = CGRect(x: inset, y: inset, width: s - inset*2, height: s - inset*2)
    let path = CGPath(roundedRect: bg, cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil)
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(red: 0.93, green: 0.93, blue: 0.95, alpha: 1),  // top light
            CGColor(red: 0.66, green: 0.66, blue: 0.70, alpha: 1)   // bottom grey
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: bg.minX, y: bg.maxY),
                           end:   CGPoint(x: bg.maxX, y: bg.minY),
                           options: [])
    ctx.restoreGState()
}

/// A classic Platinum window: beveled grey frame, pinstriped title bar with a
/// close box, white body holding a bold blue "#".
func drawWindow(ctx: CGContext, s: CGFloat) {
    let win = CGRect(x: s * 0.18, y: s * 0.20, width: s * 0.64, height: s * 0.58)
    let radius = s * 0.04

    // Window frame (light Platinum grey) with a 3D bevel.
    let framePath = CGPath(roundedRect: win, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(framePath)
    ctx.setFillColor(CGColor(red: 0.86, green: 0.86, blue: 0.88, alpha: 1))
    ctx.fillPath()

    // Bevel: light top/left, dark bottom/right.
    ctx.saveGState()
    ctx.addPath(framePath); ctx.clip()
    ctx.setLineWidth(max(1, s * 0.012))
    ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.9))
    ctx.stroke(win.insetBy(dx: s * 0.006, dy: s * 0.006))
    ctx.restoreGState()
    ctx.addPath(framePath)
    ctx.setStrokeColor(CGColor(red: 0.40, green: 0.40, blue: 0.44, alpha: 1))
    ctx.setLineWidth(max(1, s * 0.01))
    ctx.strokePath()

    // Title bar across the top of the window.
    let titleH = win.height * 0.20
    let titleRect = CGRect(x: win.minX, y: win.maxY - titleH, width: win.width, height: titleH)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: win, cornerWidth: radius, cornerHeight: radius, transform: nil))
    ctx.clip()
    ctx.setFillColor(CGColor(red: 0.80, green: 0.80, blue: 0.84, alpha: 1))
    ctx.fill(titleRect)
    // Platinum pinstripes: thin horizontal lines across the title bar.
    ctx.setStrokeColor(CGColor(red: 0.62, green: 0.62, blue: 0.68, alpha: 0.9))
    ctx.setLineWidth(max(0.5, s * 0.004))
    let stripes = 5
    for i in 0..<stripes {
        let y = titleRect.minY + titleRect.height * (CGFloat(i) + 1.2) / CGFloat(stripes + 1)
        ctx.move(to: CGPoint(x: titleRect.minX + s * 0.10, y: y))
        ctx.addLine(to: CGPoint(x: titleRect.maxX - s * 0.04, y: y))
        ctx.strokePath()
    }
    ctx.restoreGState()

    // Close box (top-left square).
    let box = CGRect(x: titleRect.minX + s * 0.03, y: titleRect.midY - s * 0.022,
                     width: s * 0.045, height: s * 0.045)
    ctx.addPath(CGPath(roundedRect: box, cornerWidth: s * 0.008, cornerHeight: s * 0.008, transform: nil))
    ctx.setFillColor(CGColor(red: 0.92, green: 0.92, blue: 0.94, alpha: 1))
    ctx.fillPath()
    ctx.addPath(CGPath(roundedRect: box, cornerWidth: s * 0.008, cornerHeight: s * 0.008, transform: nil))
    ctx.setStrokeColor(CGColor(red: 0.40, green: 0.40, blue: 0.44, alpha: 1))
    ctx.setLineWidth(max(0.5, s * 0.005))
    ctx.strokePath()

    // White window body.
    let bodyRect = CGRect(x: win.minX + s * 0.015, y: win.minY + s * 0.015,
                          width: win.width - s * 0.03,
                          height: win.height - titleH - s * 0.02)
    ctx.saveGState()
    ctx.addPath(CGPath(roundedRect: bodyRect, cornerWidth: s * 0.01, cornerHeight: s * 0.01, transform: nil))
    ctx.clip()
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fill(bodyRect)
    ctx.restoreGState()

    // Bold blue "#" centered in the body — the channel glyph.
    let glyphSize = bodyRect.height * 0.86
    let font = NSFont(name: "Monaco", size: glyphSize)
        ?? NSFont.monospacedSystemFont(ofSize: glyphSize, weight: .bold)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor(calibratedRed: 0.0, green: 0.0, blue: 0.70, alpha: 1)
    ]
    let glyph = NSAttributedString(string: "#", attributes: attrs)
    let gsize = glyph.size()
    let gx = bodyRect.midX - gsize.width / 2
    let gy = bodyRect.midY - gsize.height / 2
    NSGraphicsContext.current!.saveGraphicsState()
    glyph.draw(at: NSPoint(x: gx, y: gy))
    NSGraphicsContext.current!.restoreGraphicsState()
}

// MARK: - Output

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
    try data.write(to: outDir.appendingPathComponent(name))
    print("wrote \(name) (\(sz)×\(sz))")
}
