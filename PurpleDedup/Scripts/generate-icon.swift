#!/usr/bin/env swift
//
// generate-icon.swift
//
// Renders the PurpleDedup app icon — three offset photo cards on a purple squircle
// gradient, with a subtle "= " match indicator suggesting duplicate detection — into
// an .iconset directory. build-app.sh invokes this once and then runs `iconutil -c
// icns` to produce AppIcon.icns.
//
// All drawing is CoreGraphics so the icon is identical at every size; no bitmap
// scaling. Everything is proportional to the side length `s`, so the same code
// produces both 16×16 and 1024×1024.

import AppKit
import CoreGraphics

// MARK: - Drawing

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
    drawPhotoStack(ctx: ctx, s: s)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

/// Squircle-ish rounded rect with a deep-to-vibrant purple gradient. macOS app icons
/// use a 22% corner radius; we follow that so the icon sits cleanly next to other Mac
/// apps in the dock.
func drawBackground(ctx: CGContext, s: CGFloat) {
    let inset = s * 0.05
    let bg = CGRect(x: inset, y: inset, width: s - inset * 2, height: s - inset * 2)
    let path = CGPath(
        roundedRect: bg,
        cornerWidth: s * 0.22, cornerHeight: s * 0.22,
        transform: nil
    )
    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()

    let topColor    = CGColor(srgbRed: 0.42, green: 0.18, blue: 0.78, alpha: 1.0) // deep purple
    let bottomColor = CGColor(srgbRed: 0.69, green: 0.45, blue: 1.0,  alpha: 1.0) // vibrant
    let cs = CGColorSpaceCreateDeviceRGB()
    let gradient = CGGradient(colorsSpace: cs, colors: [topColor, bottomColor] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: 0, y: bg.maxY),
        end: CGPoint(x: 0, y: bg.minY),
        options: []
    )

    // A subtle inner highlight along the top edge — gives the icon a glassy "tile"
    // feel that matches contemporary Sequoia/Tahoe app icons.
    let highlight = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.18)
    ctx.setFillColor(highlight)
    let highlightRect = CGRect(x: bg.minX, y: bg.maxY - bg.height * 0.45, width: bg.width, height: bg.height * 0.45)
    ctx.fill(highlightRect)
    ctx.restoreGState()
}

/// Three offset rounded "photo cards" — the back two slightly skewed so the eye reads
/// them as a stack. The front card has a tiny mountain+sun glyph suggesting "this is a
/// photo," and a small dot-pair to its bottom-right hinting at duplication.
func drawPhotoStack(ctx: CGContext, s: CGFloat) {
    let cs = CGColorSpaceCreateDeviceRGB()
    let cardCorner = s * 0.06

    // Card geometry: front card is centred at ~52% horizontal, slightly above centre.
    let cardW = s * 0.50
    let cardH = s * 0.42
    let frontX = (s - cardW) / 2 + s * 0.04
    let frontY = (s - cardH) / 2 - s * 0.03

    // Back card 1: shifted up-left, rotated slightly counter-clockwise.
    drawCard(
        ctx: ctx,
        rect: CGRect(x: frontX - s * 0.10, y: frontY + s * 0.07, width: cardW, height: cardH),
        rotation: -10 * .pi / 180,
        fill: CGColor(srgbRed: 0.94, green: 0.92, blue: 1.0, alpha: 0.78),
        cornerRadius: cardCorner,
        cs: cs,
        s: s
    )
    // Back card 2: shifted up-right, rotated slightly clockwise.
    drawCard(
        ctx: ctx,
        rect: CGRect(x: frontX + s * 0.06, y: frontY + s * 0.04, width: cardW, height: cardH),
        rotation: 7 * .pi / 180,
        fill: CGColor(srgbRed: 0.97, green: 0.94, blue: 1.0, alpha: 0.88),
        cornerRadius: cardCorner,
        cs: cs,
        s: s
    )
    // Front card: full opacity, contains the photo glyph.
    let frontRect = CGRect(x: frontX, y: frontY, width: cardW, height: cardH)
    drawCard(
        ctx: ctx,
        rect: frontRect,
        rotation: 0,
        fill: CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1),
        cornerRadius: cardCorner,
        cs: cs,
        s: s
    )
    drawPhotoGlyph(ctx: ctx, in: frontRect, s: s)
    drawDuplicateBadge(ctx: ctx, near: frontRect, s: s)
}

func drawCard(
    ctx: CGContext,
    rect: CGRect,
    rotation: CGFloat,
    fill: CGColor,
    cornerRadius: CGFloat,
    cs: CGColorSpace,
    s: CGFloat
) {
    ctx.saveGState()

    // Translate to the card's centre, rotate, translate back, so rotation is around
    // its own centre instead of (0, 0).
    let centre = CGPoint(x: rect.midX, y: rect.midY)
    ctx.translateBy(x: centre.x, y: centre.y)
    ctx.rotate(by: rotation)
    ctx.translateBy(x: -centre.x, y: -centre.y)

    // Soft shadow underneath.
    ctx.setShadow(
        offset: CGSize(width: 0, height: -s * 0.012),
        blur: s * 0.03,
        color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.25)
    )

    let path = CGPath(roundedRect: rect, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    ctx.addPath(path)
    ctx.setFillColor(fill)
    ctx.fillPath()

    ctx.restoreGState()
}

/// Stylised "photo" — a horizon line with a sun above it, very small mountain peak.
/// At 16×16 this collapses into a recognizable suggestion of an image rather than
/// individual elements; that's the point.
func drawPhotoGlyph(ctx: CGContext, in rect: CGRect, s: CGFloat) {
    ctx.saveGState()

    // Sun: small purple disc in the upper-left of the card.
    let sunR = rect.height * 0.12
    let sunCentre = CGPoint(x: rect.minX + rect.width * 0.30, y: rect.minY + rect.height * 0.70)
    ctx.setFillColor(CGColor(srgbRed: 0.69, green: 0.45, blue: 1.0, alpha: 1.0))
    ctx.fillEllipse(in: CGRect(x: sunCentre.x - sunR, y: sunCentre.y - sunR, width: sunR * 2, height: sunR * 2))

    // Horizon mountains: two triangles in a slightly darker purple.
    let mountainColor = CGColor(srgbRed: 0.42, green: 0.18, blue: 0.78, alpha: 1.0)
    ctx.setFillColor(mountainColor)
    let baseY = rect.minY + rect.height * 0.30
    let leftPeakX = rect.minX + rect.width * 0.30
    let rightPeakX = rect.minX + rect.width * 0.62
    let peakY = rect.minY + rect.height * 0.62
    let peakY2 = rect.minY + rect.height * 0.55

    ctx.move(to: CGPoint(x: rect.minX + rect.width * 0.10, y: baseY))
    ctx.addLine(to: CGPoint(x: leftPeakX, y: peakY))
    ctx.addLine(to: CGPoint(x: rect.minX + rect.width * 0.50, y: baseY))
    ctx.closePath()
    ctx.fillPath()

    ctx.move(to: CGPoint(x: rect.minX + rect.width * 0.40, y: baseY))
    ctx.addLine(to: CGPoint(x: rightPeakX, y: peakY2))
    ctx.addLine(to: CGPoint(x: rect.minX + rect.width * 0.90, y: baseY))
    ctx.closePath()
    ctx.fillPath()

    // Bottom strip — slight purple bar at the very bottom of the card, hinting at a
    // photo border / film strip.
    let strip = CGRect(
        x: rect.minX + rect.width * 0.08,
        y: rect.minY + rect.height * 0.10,
        width: rect.width * 0.84,
        height: rect.height * 0.06
    )
    ctx.setFillColor(CGColor(srgbRed: 0.69, green: 0.45, blue: 1.0, alpha: 0.40))
    ctx.fill(strip)

    ctx.restoreGState()
}

/// Small "dedup" badge: a circular purple chip with two dots inside, sitting at the
/// bottom-right of the front card. Communicates "this thing finds doubles."
func drawDuplicateBadge(ctx: CGContext, near rect: CGRect, s: CGFloat) {
    let badgeR = s * 0.075
    let centre = CGPoint(x: rect.maxX - badgeR * 0.4, y: rect.minY + badgeR * 0.4)

    ctx.saveGState()
    // Drop shadow on the badge.
    ctx.setShadow(
        offset: CGSize(width: 0, height: -s * 0.008),
        blur: s * 0.02,
        color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.30)
    )
    ctx.setFillColor(CGColor(srgbRed: 0.42, green: 0.18, blue: 0.78, alpha: 1.0))
    ctx.fillEllipse(in: CGRect(
        x: centre.x - badgeR, y: centre.y - badgeR,
        width: badgeR * 2, height: badgeR * 2
    ))
    ctx.restoreGState()

    // Two white dots inside, side by side.
    let dotR = badgeR * 0.20
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillEllipse(in: CGRect(
        x: centre.x - badgeR * 0.45 - dotR, y: centre.y - dotR,
        width: dotR * 2, height: dotR * 2
    ))
    ctx.fillEllipse(in: CGRect(
        x: centre.x + badgeR * 0.45 - dotR, y: centre.y - dotR,
        width: dotR * 2, height: dotR * 2
    ))

    // Connecting bar between dots — visually says "these two are linked."
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.85))
    let barH = dotR * 0.5
    ctx.fill(CGRect(
        x: centre.x - badgeR * 0.45,
        y: centre.y - barH / 2,
        width: badgeR * 0.90,
        height: barH
    ))
}

// MARK: - Iconset writer

func writePNG(_ rep: NSBitmapImageRep, to path: URL) throws {
    let data = rep.representation(using: .png, properties: [:])!
    try data.write(to: path)
}

// Apple's required filenames for an .iconset directory. iconutil consumes this layout
// and produces an AppIcon.icns. The 1×/2× pairing means a 16pt icon ships at both 16×16
// and 32×32 pixels (Retina), and so on.
let entries: [(name: String, side: Int)] = [
    ("icon_16x16.png",       16),
    ("icon_16x16@2x.png",    32),
    ("icon_32x32.png",       32),
    ("icon_32x32@2x.png",    64),
    ("icon_128x128.png",    128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png",    256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png",    512),
    ("icon_512x512@2x.png", 1024),
]

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write(Data("usage: generate-icon.swift <iconset-dir>\n".utf8))
    exit(2)
}
let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

for entry in entries {
    let rep = drawTile(side: CGFloat(entry.side))
    let url = outDir.appendingPathComponent(entry.name)
    try writePNG(rep, to: url)
    FileHandle.standardError.write(Data("\(entry.name) (\(entry.side)px)\n".utf8))
}
print("Wrote iconset to \(outDir.path)")
