#!/usr/bin/env swift
import AppKit
import Foundation

let iconsetDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "/tmp/WeightTracker.iconset"

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

// Draw into a CGBitmapContext at exact pixel count — avoids Retina scale-factor inflation
func drawIcon(into ctx: CGContext, pixels: Int) {
    let s = CGFloat(pixels)
    // Wrap the CGContext so NSBezierPath / NSImage draw into it
    let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: false)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx

    let radius   = s * 0.225
    let iconRect = NSRect(x: 0, y: 0, width: s, height: s)
    let roundRect = NSBezierPath(roundedRect: iconRect, xRadius: radius, yRadius: radius)

    ctx.saveGState()
    roundRect.addClip()

    // ── Background: vibrant sky-blue → deep indigo ────────────────────────────
    let bgTop    = CGColor(red: 0.20, green: 0.58, blue: 0.98, alpha: 1)
    let bgBottom = CGColor(red: 0.29, green: 0.16, blue: 0.82, alpha: 1)
    let bgGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: [bgTop, bgBottom] as CFArray,
                             locations: [0.0, 1.0])!
    ctx.drawLinearGradient(bgGrad,
                            start: CGPoint(x: s * 0.15, y: s),
                            end:   CGPoint(x: s * 0.85, y: 0),
                            options: [])

    // ── Radial glow centred on the symbol ─────────────────────────────────────
    let glowColors = [CGColor(gray: 1, alpha: 0.22), CGColor(gray: 1, alpha: 0)]
    let glowGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: glowColors as CFArray,
                               locations: [0.0, 1.0])!
    ctx.drawRadialGradient(glowGrad,
                            startCenter: CGPoint(x: s * 0.50, y: s * 0.58),
                            startRadius: 0,
                            endCenter:   CGPoint(x: s * 0.50, y: s * 0.58),
                            endRadius:   s * 0.42,
                            options: [])

    ctx.restoreGState()

    // ── Scale symbol (white) ──────────────────────────────────────────────────
    // Strategy: render symbol (black on transparent) into a scratch bitmap, then
    // fill a second bitmap with white and use destinationIn to cut the symbol shape
    // into it → white symbol on transparent → composite into main ctx.
    let symSide = s * 0.52
    let symX    = (s - symSide) / 2
    let symY    = s * 0.35
    let iSym    = max(1, Int(symSide))
    let symCfg  = NSImage.SymbolConfiguration(pointSize: symSide * 0.70, weight: .semibold)

    if let sym = NSImage(systemSymbolName: "scalemass.fill", accessibilityDescription: nil)?
            .withSymbolConfiguration(symCfg),
       let alphaCtx = CGContext(data: nil, width: iSym, height: iSym,
                                 bitsPerComponent: 8, bytesPerRow: 0,
                                 space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
       let whiteCtx = CGContext(data: nil, width: iSym, height: iSym,
                                 bitsPerComponent: 8, bytesPerRow: 0,
                                 space: CGColorSpaceCreateDeviceRGB(),
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {

        // 1. Draw symbol (black on transparent) into alphaCtx
        let alphaNSCtx = NSGraphicsContext(cgContext: alphaCtx, flipped: false)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = alphaNSCtx
        sym.draw(in: NSRect(x: 0, y: 0, width: symSide, height: symSide),
                 from: NSRect.zero, operation: .sourceOver, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        // 2. In whiteCtx: fill with white, then mask to symbol's alpha via destinationIn
        whiteCtx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.95))
        whiteCtx.fill(CGRect(x: 0, y: 0, width: iSym, height: iSym))
        if let alphaMask = alphaCtx.makeImage() {
            whiteCtx.setBlendMode(.destinationIn)
            whiteCtx.draw(alphaMask, in: CGRect(x: 0, y: 0, width: iSym, height: iSym))
        }

        // 3. Composite white symbol into main ctx
        if let whiteSymbol = whiteCtx.makeImage() {
            ctx.draw(whiteSymbol, in: CGRect(x: symX, y: symY, width: symSide, height: symSide))
        }

        // Restore main context's NSGraphicsContext wrapper
        NSGraphicsContext.current = nsCtx
    }

    // ── Trend line: smooth bezier descending left→right ───────────────────────
    let tPad: CGFloat = s * 0.11
    let tA = CGPoint(x: tPad,       y: s * 0.225)
    let tB = CGPoint(x: s * 0.35,   y: s * 0.175)
    let tC = CGPoint(x: s * 0.58,   y: s * 0.130)
    let tD = CGPoint(x: s - tPad,   y: s * 0.155)

    let trendPath = NSBezierPath()
    trendPath.lineWidth    = max(1.5, s * 0.026)
    trendPath.lineCapStyle  = .round
    trendPath.lineJoinStyle = .round
    trendPath.move(to: tA)
    trendPath.curve(to: tB,
                    controlPoint1: CGPoint(x: tA.x + (tB.x - tA.x) * 0.5, y: tA.y),
                    controlPoint2: CGPoint(x: tA.x + (tB.x - tA.x) * 0.5, y: tB.y))
    trendPath.curve(to: tD,
                    controlPoint1: CGPoint(x: tB.x + (tD.x - tB.x) * 0.4, y: tB.y),
                    controlPoint2: CGPoint(x: tB.x + (tD.x - tB.x) * 0.7, y: tD.y - (tD.y - tC.y) * 0.4))

    NSColor(calibratedRed: 0.30, green: 0.95, blue: 0.62, alpha: 0.92).setStroke()
    trendPath.stroke()

    // Data point dots
    let dotR    = max(1.5, s * 0.028)
    let dotFill = NSColor(calibratedRed: 0.30, green: 0.95, blue: 0.62, alpha: 1.0)
    let dotRing = NSColor(white: 1.0, alpha: 0.85)
    let ringW   = max(0.8, s * 0.007)
    for pt in [tA, tB, tC, tD] {
        let r = NSRect(x: pt.x - dotR, y: pt.y - dotR, width: dotR * 2, height: dotR * 2)
        dotFill.setFill(); NSBezierPath(ovalIn: r).fill()
        dotRing.setStroke()
        let ring = NSBezierPath(ovalIn: r.insetBy(dx: -ringW, dy: -ringW))
        ring.lineWidth = ringW; ring.stroke()
    }

    // ── Top highlight (glass sheen) ────────────────────────────────────────────
    ctx.saveGState()
    roundRect.addClip()
    let hlColors = [CGColor(gray: 1, alpha: 0.28), CGColor(gray: 1, alpha: 0)]
    let hlGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: hlColors as CFArray,
                             locations: [0.0, 1.0])!
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
