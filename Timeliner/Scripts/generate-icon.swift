#!/usr/bin/env swift
import AppKit
import Foundation

let iconsetDir = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "/tmp/Timeliner.iconset"

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

    // Background gradient — deep blue → teal (timeline / archive vibe)
    ctx.saveGState()
    roundRect.addClip()
    let bgTop    = CGColor(red: 0.10, green: 0.20, blue: 0.45, alpha: 1)
    let bgBottom = CGColor(red: 0.04, green: 0.08, blue: 0.20, alpha: 1)
    let bgGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: [bgTop, bgBottom] as CFArray,
                             locations: [0.0, 1.0])!
    ctx.drawLinearGradient(bgGrad,
                            start: CGPoint(x: s * 0.15, y: s),
                            end:   CGPoint(x: s * 0.85, y: 0),
                            options: [])
    ctx.restoreGState()

    // Horizontal timeline track across the middle
    let trackY = s * 0.50
    let trackHeight = max(1.5, s * 0.012)
    let trackStart = s * 0.14
    let trackEnd = s * 0.86
    NSColor(white: 1, alpha: 0.55).setFill()
    let trackRect = NSRect(x: trackStart, y: trackY - trackHeight / 2,
                            width: trackEnd - trackStart, height: trackHeight)
    NSBezierPath(roundedRect: trackRect, xRadius: trackHeight / 2, yRadius: trackHeight / 2).fill()

    // Tick marks along the track
    let tickCount = 7
    let tickHeight = s * 0.05
    let tickWidth = max(1, s * 0.012)
    NSColor(white: 1, alpha: 0.45).setFill()
    for i in 0..<tickCount {
        let frac = CGFloat(i) / CGFloat(tickCount - 1)
        let x = trackStart + (trackEnd - trackStart) * frac
        let r = NSRect(x: x - tickWidth / 2, y: trackY - tickHeight / 2,
                        width: tickWidth, height: tickHeight)
        NSBezierPath(rect: r).fill()
    }

    // Event "pins" — three colored circles at meaningful points
    let pinPositions: [(CGFloat, NSColor)] = [
        (0.20, NSColor(calibratedRed: 1.00, green: 0.62, blue: 0.20, alpha: 1)),  // amber
        (0.50, NSColor(calibratedRed: 0.95, green: 0.30, blue: 0.55, alpha: 1)),  // pink
        (0.80, NSColor(calibratedRed: 0.40, green: 0.85, blue: 0.55, alpha: 1)),  // mint
    ]
    let pinRadius = s * 0.075
    for (frac, color) in pinPositions {
        let x = trackStart + (trackEnd - trackStart) * frac
        let pinCenter = CGPoint(x: x, y: trackY)
        // Halo
        ctx.saveGState()
        let haloColors = [color.withAlphaComponent(0.45).cgColor, color.withAlphaComponent(0).cgColor]
        let haloGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                   colors: haloColors as CFArray, locations: [0.0, 1.0])!
        ctx.drawRadialGradient(haloGrad,
                                startCenter: pinCenter, startRadius: 0,
                                endCenter: pinCenter, endRadius: pinRadius * 2.2,
                                options: [])
        ctx.restoreGState()
        // Pin body
        color.setFill()
        let pinPath = NSBezierPath(ovalIn: NSRect(x: x - pinRadius, y: trackY - pinRadius,
                                                     width: pinRadius * 2, height: pinRadius * 2))
        pinPath.fill()
        // Inner highlight
        NSColor(white: 1, alpha: 0.5).setFill()
        let innerR = pinRadius * 0.32
        NSBezierPath(ovalIn: NSRect(x: x - innerR + pinRadius * 0.18,
                                     y: trackY - innerR + pinRadius * 0.18,
                                     width: innerR * 2, height: innerR * 2)).fill()
    }

    // Top sheen
    ctx.saveGState()
    roundRect.addClip()
    let hlColors = [CGColor(gray: 1, alpha: 0.20), CGColor(gray: 1, alpha: 0)]
    let hlGrad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: hlColors as CFArray, locations: [0.0, 1.0])!
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
