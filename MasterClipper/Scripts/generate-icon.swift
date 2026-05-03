#!/usr/bin/env swift
import AppKit
import Foundation

let iconsetDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "/tmp/MasterClipper.iconset"

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

    // ── Background gradient: violet → indigo ─────────────────────────────────
    ctx.saveGState()
    roundRect.addClip()

    let bgTop    = CGColor(red: 0.48, green: 0.31, blue: 1.00, alpha: 1)
    let bgBottom = CGColor(red: 0.18, green: 0.08, blue: 0.46, alpha: 1)
    let bgGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: [bgTop, bgBottom] as CFArray,
                             locations: [0.0, 1.0])!
    ctx.drawLinearGradient(bgGrad,
                            start: CGPoint(x: s * 0.15, y: s),
                            end:   CGPoint(x: s * 0.85, y: 0),
                            options: [])

    // Subtle radial glow
    let glowColors = [CGColor(gray: 1, alpha: 0.18), CGColor(gray: 1, alpha: 0)]
    let glowGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: glowColors as CFArray, locations: [0.0, 1.0])!
    ctx.drawRadialGradient(glowGrad,
                            startCenter: CGPoint(x: s * 0.5, y: s * 0.55),
                            startRadius: 0,
                            endCenter:   CGPoint(x: s * 0.5, y: s * 0.55),
                            endRadius:   s * 0.45,
                            options: [])
    ctx.restoreGState()

    // ── Clapperboard ─────────────────────────────────────────────────────────
    // Canvas geometry: clapperboard sits centered, slate body 60% of icon area,
    // top stick 22% tall, slightly tilted up on the left to suggest the open snap.

    let bodyW: CGFloat = s * 0.66
    let bodyH: CGFloat = s * 0.42
    let bodyX: CGFloat = (s - bodyW) / 2
    let bodyY: CGFloat = s * 0.16

    // Slate body — near-black with a faint highlight
    let bodyRect = NSRect(x: bodyX, y: bodyY, width: bodyW, height: bodyH)
    let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: s * 0.025, yRadius: s * 0.025)

    ctx.saveGState()
    bodyPath.addClip()
    let bodyTop    = CGColor(red: 0.10, green: 0.10, blue: 0.13, alpha: 1)
    let bodyBottom = CGColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1)
    let bodyGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                               colors: [bodyTop, bodyBottom] as CFArray,
                               locations: [0.0, 1.0])!
    ctx.drawLinearGradient(bodyGrad,
                            start: CGPoint(x: bodyX, y: bodyY + bodyH),
                            end:   CGPoint(x: bodyX, y: bodyY),
                            options: [])
    ctx.restoreGState()

    // Slate horizontal write-on lines
    NSColor(white: 1.0, alpha: 0.15).setStroke()
    for i in 1...3 {
        let lineY = bodyY + bodyH * CGFloat(i) / 4.0
        let p = NSBezierPath()
        p.move(to: NSPoint(x: bodyX + bodyW * 0.07, y: lineY))
        p.line(to: NSPoint(x: bodyX + bodyW * 0.93, y: lineY))
        p.lineWidth = max(0.6, s * 0.005)
        p.stroke()
    }

    // ── Top sticks (the clap part) ────────────────────────────────────────────
    // Two horizontal slats each ~10% tall stacked; the upper one is hinged on the
    // left and rotated slightly up to suggest "open".

    let stickH: CGFloat = s * 0.10
    let lowerY: CGFloat = bodyY + bodyH + s * 0.005
    let lowerRect = NSRect(x: bodyX, y: lowerY, width: bodyW, height: stickH)

    drawStripedStick(rect: lowerRect, in: ctx, sScale: s, rotated: false, hinge: nil)

    // Upper stick rotated about the lower-left corner of its bounding box
    ctx.saveGState()
    let hinge = NSPoint(x: bodyX + s * 0.01, y: lowerY + stickH + s * 0.002)
    ctx.translateBy(x: hinge.x, y: hinge.y)
    ctx.rotate(by: 12 * .pi / 180)
    ctx.translateBy(x: -hinge.x, y: -hinge.y)
    let upperRect = NSRect(x: bodyX, y: lowerY + stickH + s * 0.002, width: bodyW, height: stickH)
    drawStripedStick(rect: upperRect, in: ctx, sScale: s, rotated: true, hinge: hinge)
    ctx.restoreGState()

    // ── Top sheen ─────────────────────────────────────────────────────────────
    ctx.saveGState()
    roundRect.addClip()
    let hlColors = [CGColor(gray: 1, alpha: 0.22), CGColor(gray: 1, alpha: 0)]
    let hlGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: hlColors as CFArray, locations: [0.0, 1.0])!
    ctx.drawLinearGradient(hlGrad,
                            start: CGPoint(x: s * 0.5, y: s),
                            end:   CGPoint(x: s * 0.5, y: s * 0.72),
                            options: [])
    ctx.restoreGState()

    NSGraphicsContext.restoreGraphicsState()
}

func drawStripedStick(rect: NSRect, in ctx: CGContext, sScale s: CGFloat, rotated: Bool, hinge: NSPoint?) {
    // Background of the stick — dark grey
    let path = NSBezierPath(roundedRect: rect, xRadius: s * 0.015, yRadius: s * 0.015)
    NSColor(calibratedRed: 0.12, green: 0.12, blue: 0.14, alpha: 1).setFill()
    path.fill()

    // Diagonal white-and-black stripes inside the stick
    ctx.saveGState()
    path.addClip()

    let stripeCount = 6
    let stripeW = rect.width / CGFloat(stripeCount)
    let extra: CGFloat = rect.height * 1.2     // overhang for the diagonal
    for i in -1...stripeCount + 1 {
        // Alternating black/white stripes drawn as parallelograms (diagonal)
        let isWhite = (i % 2) == 0
        if isWhite {
            NSColor(white: 0.92, alpha: 1).setFill()
        } else {
            continue                            // black already from background
        }
        let p = NSBezierPath()
        let x0 = rect.minX + CGFloat(i) * stripeW
        p.move(to: NSPoint(x: x0,           y: rect.minY))
        p.line(to: NSPoint(x: x0 + stripeW, y: rect.minY))
        p.line(to: NSPoint(x: x0 + stripeW + extra, y: rect.maxY))
        p.line(to: NSPoint(x: x0 + extra,   y: rect.maxY))
        p.close()
        p.fill()
    }
    ctx.restoreGState()

    // Subtle outline
    NSColor(white: 0, alpha: 0.4).setStroke()
    path.lineWidth = max(0.5, s * 0.004)
    path.stroke()
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
