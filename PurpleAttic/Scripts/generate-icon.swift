#!/usr/bin/env swift
//
// generate-icon.swift
//
// Renders the PurpleAttic app icon — a white archive box on a purple squircle with a photo
// card dropping into it and a downward chevron (the "offload to archive" motion) — into an
// .iconset directory. build-app.sh invokes this, then `iconutil -c icns` produces
// AppIcon.icns. All drawing is CoreGraphics and proportional to side `s`, so the same code
// renders every size byte-identically (the multi-Mac/code-generated-icon requirement).

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
    drawPhotoCard(ctx: ctx, s: s)
    drawArchiveBox(ctx: ctx, s: s)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Purple squircle with a deep→vibrant vertical gradient (matches the PhantomLives family).
func drawBackground(ctx: CGContext, s: CGFloat) {
    let inset = s * 0.05
    let bg = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = CGPath(roundedRect: bg, cornerWidth: s * 0.22, cornerHeight: s * 0.22, transform: nil)
    ctx.saveGState()
    ctx.addPath(path); ctx.clip()
    let cs = CGColorSpaceCreateDeviceRGB()
    let top = CGColor(srgbRed: 0.42, green: 0.18, blue: 0.78, alpha: 1.0)
    let bottom = CGColor(srgbRed: 0.69, green: 0.45, blue: 1.0, alpha: 1.0)
    let gradient = CGGradient(colorsSpace: cs, colors: [top, bottom] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 0, y: bg.maxY), end: CGPoint(x: 0, y: bg.minY), options: [])
    let highlight = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.16)
    ctx.setFillColor(highlight)
    ctx.fill(CGRect(x: bg.minX, y: bg.maxY - bg.height * 0.42, width: bg.width, height: bg.height * 0.42))
    ctx.restoreGState()
}

/// A photo card in the upper area, tilted slightly, "descending" into the box below — with a
/// small down-chevron above it suggesting the offload motion.
func drawPhotoCard(ctx: CGContext, s: CGFloat) {
    // Down chevron at the very top-centre.
    ctx.saveGState()
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.9))
    ctx.setLineWidth(s * 0.035)
    ctx.setLineCap(.round); ctx.setLineJoin(.round)
    let cx = s * 0.5, topY = s * 0.80
    ctx.move(to: CGPoint(x: cx - s * 0.07, y: topY))
    ctx.addLine(to: CGPoint(x: cx, y: topY - s * 0.06))
    ctx.addLine(to: CGPoint(x: cx + s * 0.07, y: topY))
    ctx.strokePath()
    ctx.restoreGState()

    // Photo card.
    let cardW = s * 0.34, cardH = s * 0.27
    let rect = CGRect(x: (s - cardW) / 2, y: s * 0.46, width: cardW, height: cardH)
    ctx.saveGState()
    let centre = CGPoint(x: rect.midX, y: rect.midY)
    ctx.translateBy(x: centre.x, y: centre.y); ctx.rotate(by: -6 * .pi / 180); ctx.translateBy(x: -centre.x, y: -centre.y)
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.01), blur: s * 0.025,
                  color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.22))
    ctx.addPath(CGPath(roundedRect: rect, cornerWidth: s * 0.04, cornerHeight: s * 0.04, transform: nil))
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1)); ctx.fillPath()
    // mini photo glyph: sun + mountain
    ctx.setFillColor(CGColor(srgbRed: 0.69, green: 0.45, blue: 1.0, alpha: 1))
    let sunR = rect.height * 0.13
    ctx.fillEllipse(in: CGRect(x: rect.minX + rect.width * 0.24 - sunR, y: rect.minY + rect.height * 0.60 - sunR,
                               width: sunR * 2, height: sunR * 2))
    ctx.setFillColor(CGColor(srgbRed: 0.42, green: 0.18, blue: 0.78, alpha: 1))
    let baseY = rect.minY + rect.height * 0.30
    ctx.move(to: CGPoint(x: rect.minX + rect.width * 0.16, y: baseY))
    ctx.addLine(to: CGPoint(x: rect.minX + rect.width * 0.46, y: rect.minY + rect.height * 0.66))
    ctx.addLine(to: CGPoint(x: rect.minX + rect.width * 0.74, y: baseY))
    ctx.closePath(); ctx.fillPath()
    ctx.restoreGState()
}

/// A white archive box (open, with a lid band) sitting across the lower third.
func drawArchiveBox(ctx: CGContext, s: CGFloat) {
    let boxW = s * 0.56, boxH = s * 0.26
    let box = CGRect(x: (s - boxW) / 2, y: s * 0.16, width: boxW, height: boxH)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03,
                  color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.25))
    // Body
    ctx.addPath(CGPath(roundedRect: box, cornerWidth: s * 0.03, cornerHeight: s * 0.03, transform: nil))
    ctx.setFillColor(CGColor(srgbRed: 0.96, green: 0.95, blue: 1.0, alpha: 1)); ctx.fillPath()
    ctx.restoreGState()
    // Lid band across the top of the box
    let lid = CGRect(x: box.minX - s * 0.02, y: box.maxY - s * 0.055, width: boxW + s * 0.04, height: s * 0.075)
    ctx.addPath(CGPath(roundedRect: lid, cornerWidth: s * 0.02, cornerHeight: s * 0.02, transform: nil))
    ctx.setFillColor(CGColor(srgbRed: 0.85, green: 0.80, blue: 0.98, alpha: 1)); ctx.fillPath()
    // Handle notch
    let notch = CGRect(x: box.midX - s * 0.05, y: lid.minY + s * 0.018, width: s * 0.10, height: s * 0.022)
    ctx.addPath(CGPath(roundedRect: notch, cornerWidth: s * 0.011, cornerHeight: s * 0.011, transform: nil))
    ctx.setFillColor(CGColor(srgbRed: 0.55, green: 0.45, blue: 0.85, alpha: 1)); ctx.fillPath()
}

func writePNG(_ rep: NSBitmapImageRep, to path: URL) throws {
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: path)
}

let entries: [(name: String, side: Int)] = [
    ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024),
]

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: generate-icon.swift <iconset-dir>\n".utf8))
    exit(2)
}
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)
for entry in entries {
    let rep = drawTile(side: CGFloat(entry.side))
    try writePNG(rep, to: outDir.appendingPathComponent(entry.name))
    FileHandle.standardError.write(Data("\(entry.name) (\(entry.side)px)\n".utf8))
}
print("Wrote iconset to \(outDir.path)")
