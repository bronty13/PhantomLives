#!/usr/bin/env swift
//
// generate-icon.swift
//
// Renders the PurpleIRC app icon — a cute chunky purple dinosaur with "IRC"
// across the top — into an .iconset directory. build-app.sh invokes this once
// and then runs `iconutil -c icns` to produce AppIcon.icns.
//
// All drawing is CoreGraphics so the result is identical at every size; no
// bitmap scaling. Everything lives off proportions of `s`, so the same code
// produces both 16×16 and 1024×1024.

import AppKit
import CoreGraphics

// MARK: - Drawing

/// Draw a single icon tile of side `s` into a fresh bitmap.
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
    drawDinosaur(ctx: ctx, s: s)
    drawIRCText(ctx: ctx, s: s)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Rounded-rectangle purple gradient background, macOS squircle-ish.
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
            CGColor(red: 0.78, green: 0.60, blue: 0.98, alpha: 1),
            CGColor(red: 0.42, green: 0.22, blue: 0.72, alpha: 1)
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

/// A simple friendly cartoon dinosaur: chunky body, round head, big eye,
/// tiny arm, two stubby legs, little back spikes. Origin = bottom-left.
func drawDinosaur(ctx: CGContext, s: CGFloat) {
    let bodyColor  = CGColor(red: 0.62, green: 0.36, blue: 0.90, alpha: 1)
    let bellyColor = CGColor(red: 0.95, green: 0.82, blue: 0.98, alpha: 1)
    let darkPurple = CGColor(red: 0.28, green: 0.12, blue: 0.48, alpha: 1)
    let white      = CGColor(red: 1, green: 1, blue: 1, alpha: 1)
    let spikeColor = CGColor(red: 0.98, green: 0.80, blue: 0.45, alpha: 1)

    // --- Body (chunky oval, centered-ish)
    let body = CGRect(x: s * 0.22, y: s * 0.22, width: s * 0.55, height: s * 0.40)
    ctx.setFillColor(bodyColor)
    ctx.fillEllipse(in: body)

    // --- Tail: a triangle wedge off the back-left of the body.
    let tail = CGMutablePath()
    tail.move(to:    CGPoint(x: s * 0.22, y: s * 0.38))
    tail.addLine(to: CGPoint(x: s * 0.08, y: s * 0.50))
    tail.addLine(to: CGPoint(x: s * 0.25, y: s * 0.48))
    tail.closeSubpath()
    ctx.addPath(tail)
    ctx.setFillColor(bodyColor)
    ctx.fillPath()

    // --- Belly highlight (lighter oval overlapping the lower body).
    let belly = CGRect(x: s * 0.30, y: s * 0.24, width: s * 0.38, height: s * 0.22)
    ctx.setFillColor(bellyColor)
    ctx.fillEllipse(in: belly)

    // --- Back spikes: three small triangles along the upper curve.
    ctx.setFillColor(spikeColor)
    for (x, h) in [(0.40, 0.04), (0.50, 0.055), (0.60, 0.045)] {
        let spike = CGMutablePath()
        spike.move(to:    CGPoint(x: s * CGFloat(x) - s * 0.02, y: s * 0.60))
        spike.addLine(to: CGPoint(x: s * CGFloat(x) + s * 0.02, y: s * 0.60))
        spike.addLine(to: CGPoint(x: s * CGFloat(x),
                                  y: s * 0.60 + s * CGFloat(h)))
        spike.closeSubpath()
        ctx.addPath(spike)
        ctx.fillPath()
    }

    // --- Head (big round circle on top-right of body).
    let head = CGRect(x: s * 0.58, y: s * 0.46, width: s * 0.30, height: s * 0.28)
    ctx.setFillColor(bodyColor)
    ctx.fillEllipse(in: head)

    // --- Snout: a little rounded rectangle at the front of the head.
    let snout = CGRect(x: s * 0.80, y: s * 0.50, width: s * 0.12, height: s * 0.12)
    let snoutPath = CGPath(roundedRect: snout,
                           cornerWidth: s * 0.05, cornerHeight: s * 0.05,
                           transform: nil)
    ctx.addPath(snoutPath)
    ctx.setFillColor(bodyColor)
    ctx.fillPath()

    // --- Nostril (tiny dark dot).
    ctx.setFillColor(darkPurple)
    ctx.fillEllipse(in: CGRect(x: s * 0.88, y: s * 0.58, width: s * 0.018, height: s * 0.018))

    // --- Mouth (small curved line).
    ctx.saveGState()
    ctx.setStrokeColor(darkPurple)
    ctx.setLineWidth(max(1, s * 0.012))
    ctx.setLineCap(.round)
    ctx.move(to:      CGPoint(x: s * 0.80, y: s * 0.53))
    ctx.addLine(to:   CGPoint(x: s * 0.88, y: s * 0.52))
    ctx.strokePath()
    ctx.restoreGState()

    // --- Eye: white circle + dark pupil + tiny highlight.
    let eyeWhite = CGRect(x: s * 0.66, y: s * 0.58, width: s * 0.10, height: s * 0.10)
    ctx.setFillColor(white)
    ctx.fillEllipse(in: eyeWhite)
    let pupil = CGRect(x: s * 0.70, y: s * 0.60, width: s * 0.045, height: s * 0.055)
    ctx.setFillColor(darkPurple)
    ctx.fillEllipse(in: pupil)
    let glint = CGRect(x: s * 0.715, y: s * 0.635, width: s * 0.018, height: s * 0.018)
    ctx.setFillColor(white)
    ctx.fillEllipse(in: glint)

    // --- Tiny arm (short oval dangling off the body).
    let arm = CGRect(x: s * 0.54, y: s * 0.38, width: s * 0.07, height: s * 0.14)
    ctx.setFillColor(bodyColor)
    ctx.fillEllipse(in: arm)

    // --- Two stubby legs.
    for x in [0.34, 0.56] {
        let leg = CGRect(x: s * CGFloat(x), y: s * 0.16,
                         width: s * 0.10, height: s * 0.12)
        let legPath = CGPath(roundedRect: leg,
                             cornerWidth: s * 0.035, cornerHeight: s * 0.035,
                             transform: nil)
        ctx.addPath(legPath)
        ctx.setFillColor(bodyColor)
        ctx.fillPath()
    }
}

/// "IRC" across the top of the tile, in bold white.
func drawIRCText(ctx: CGContext, s: CGFloat) {
    let text = "IRC"
    let fontSize = s * 0.22
    let font = NSFont.systemFont(ofSize: fontSize, weight: .black)
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = s * 0.01
    shadow.shadowOffset = NSSize(width: 0, height: -s * 0.006)
    let attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: NSColor.white,
        .shadow: shadow,
        .kern: s * 0.01
    ]
    let attributed = NSAttributedString(string: text, attributes: attrs)
    let textSize = attributed.size()
    // Origin = bottom-left, so "top" of the icon is high Y. We want the text
    // centered horizontally, sitting just below the rounded top edge.
    let x = (s - textSize.width) / 2
    let y = s - s * 0.18 - textSize.height / 2
    NSGraphicsContext.current!.saveGraphicsState()
    attributed.draw(at: NSPoint(x: x, y: y))
    NSGraphicsContext.current!.restoreGraphicsState()
    _ = ctx // appease unused-param warning
}

// MARK: - Output

/// All .iconset variants macOS consumes. Each tuple is (pixel size, file name).
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
