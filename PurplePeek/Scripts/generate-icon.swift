#!/usr/bin/env swift
//
// generate-icon.swift
//
// Renders the PurplePeek app icon — a magnifying glass whose lens holds an eye iris (the
// "peek / inspect media" idea) on a purple squircle — into an .iconset directory.
// build-app.sh invokes this, then `iconutil -c icns` produces AppIcon.icns. All drawing is
// CoreGraphics and proportional to side `s`, so the same code renders every size
// byte-identically (the multi-Mac / code-generated-icon requirement).

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
    drawMagnifier(ctx: ctx, s: s)

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

/// A white magnifying glass: a thick lens ring, a diagonal handle, and an eye (almond +
/// iris + pupil + glint) nested inside the lens.
func drawMagnifier(ctx: CGContext, s: CGFloat) {
    // Lens geometry: a circle in the upper-left-of-centre, handle going to lower-right.
    let lensCenter = CGPoint(x: s * 0.44, y: s * 0.56)
    let lensRadius = s * 0.235
    let ringWidth = s * 0.055

    // ---- Handle (drawn first so the lens ring overlaps its top end) ----
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.025,
                  color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.25))
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.setLineWidth(s * 0.085)
    ctx.setLineCap(.round)
    let handleStart = CGPoint(
        x: lensCenter.x + cos(-CGFloat.pi / 4) * (lensRadius + ringWidth * 0.2),
        y: lensCenter.y + sin(-CGFloat.pi / 4) * (lensRadius + ringWidth * 0.2)
    )
    let handleEnd = CGPoint(x: s * 0.74, y: s * 0.26)
    ctx.move(to: handleStart)
    ctx.addLine(to: handleEnd)
    ctx.strokePath()
    ctx.restoreGState()

    // ---- Lens ring (white) ----
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -s * 0.012), blur: s * 0.03,
                  color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.22))
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.setLineWidth(ringWidth)
    ctx.addArc(center: lensCenter, radius: lensRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
    ctx.strokePath()
    ctx.restoreGState()

    // ---- Lens interior fill (translucent white so the purple shows through faintly) ----
    let innerRadius = lensRadius - ringWidth / 2
    ctx.saveGState()
    ctx.addArc(center: lensCenter, radius: innerRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.14))
    ctx.fillPath()
    ctx.restoreGState()

    // ---- Eye inside the lens: almond outline + iris + pupil + glint ----
    ctx.saveGState()
    // Clip to the lens interior so the eye never spills past the ring.
    ctx.addArc(center: lensCenter, radius: innerRadius, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
    ctx.clip()

    // Almond eye shape (two arcs), white.
    let eyeW = innerRadius * 1.7
    let eyeH = innerRadius * 0.95
    let left = CGPoint(x: lensCenter.x - eyeW / 2, y: lensCenter.y)
    let right = CGPoint(x: lensCenter.x + eyeW / 2, y: lensCenter.y)
    ctx.move(to: left)
    ctx.addQuadCurve(to: right, control: CGPoint(x: lensCenter.x, y: lensCenter.y + eyeH))
    ctx.addQuadCurve(to: left, control: CGPoint(x: lensCenter.x, y: lensCenter.y - eyeH))
    ctx.closePath()
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.fillPath()

    // Iris (purple).
    let irisR = innerRadius * 0.46
    ctx.setFillColor(CGColor(srgbRed: 0.50, green: 0.24, blue: 0.86, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: lensCenter.x - irisR, y: lensCenter.y - irisR, width: irisR * 2, height: irisR * 2))

    // Pupil (deep purple/black).
    let pupilR = irisR * 0.5
    ctx.setFillColor(CGColor(srgbRed: 0.16, green: 0.06, blue: 0.34, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: lensCenter.x - pupilR, y: lensCenter.y - pupilR, width: pupilR * 2, height: pupilR * 2))

    // Catch-light glint (white), upper-right of the pupil.
    let glintR = pupilR * 0.42
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.95))
    ctx.fillEllipse(in: CGRect(x: lensCenter.x + pupilR * 0.2, y: lensCenter.y + pupilR * 0.2,
                               width: glintR * 2, height: glintR * 2))
    ctx.restoreGState()
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
