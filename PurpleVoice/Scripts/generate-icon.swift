#!/usr/bin/env swift
import AppKit
import CoreGraphics

// Generates PurpleVoice's macOS iconset PNGs at all required 1x/2x sizes.
// Style: purple rounded-square tile with a white microphone and subtle voice
// wave arcs.

guard CommandLine.arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: generate-icon.swift <out-iconset-dir>\n".utf8))
    exit(2)
}

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])
try? FileManager.default.createDirectory(at: outDir, withIntermediateDirectories: true)

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

func radians(_ degrees: CGFloat) -> CGFloat {
    degrees * .pi / 180
}

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

    let bgInset = s * 0.05
    let bgRect = CGRect(x: bgInset, y: bgInset, width: s - bgInset * 2, height: s - bgInset * 2)
    let bgPath = CGPath(
        roundedRect: bgRect,
        cornerWidth: s * 0.22,
        cornerHeight: s * 0.22,
        transform: nil
    )

    ctx.saveGState()
    ctx.addPath(bgPath)
    ctx.clip()

    let top = CGColor(srgbRed: 0.73, green: 0.53, blue: 0.97, alpha: 1.0)
    let bottom = CGColor(srgbRed: 0.34, green: 0.18, blue: 0.62, alpha: 1.0)
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [top, bottom] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        gradient,
        start: CGPoint(x: bgRect.midX, y: bgRect.maxY),
        end: CGPoint(x: bgRect.midX, y: bgRect.minY),
        options: []
    )

    let topSheen = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.22),
            CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.0),
        ] as CFArray,
        locations: [0, 1]
    )!
    ctx.drawLinearGradient(
        topSheen,
        start: CGPoint(x: bgRect.midX, y: bgRect.maxY),
        end: CGPoint(x: bgRect.midX, y: bgRect.maxY - bgRect.height * 0.42),
        options: []
    )
    ctx.restoreGState()

    // Microphone body (capsule).
    let micW = s * 0.23
    let micH = s * 0.36
    let micRect = CGRect(
        x: (s - micW) / 2,
        y: s * 0.44 - micH / 2,
        width: micW,
        height: micH
    )
    let micPath = CGPath(
        roundedRect: micRect,
        cornerWidth: micW * 0.5,
        cornerHeight: micW * 0.5,
        transform: nil
    )
    ctx.addPath(micPath)
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.96))
    ctx.fillPath()

    // Grill slot.
    let slotRect = CGRect(
        x: micRect.minX + micW * 0.28,
        y: micRect.minY + micH * 0.16,
        width: micW * 0.44,
        height: micH * 0.68
    )
    let slotPath = CGPath(
        roundedRect: slotRect,
        cornerWidth: micW * 0.15,
        cornerHeight: micW * 0.15,
        transform: nil
    )
    ctx.addPath(slotPath)
    ctx.setFillColor(CGColor(srgbRed: 0.53, green: 0.36, blue: 0.83, alpha: 0.45))
    ctx.fillPath()

    // Stem and base.
    let stemRect = CGRect(
        x: s * 0.488,
        y: micRect.minY - s * 0.13,
        width: s * 0.024,
        height: s * 0.16
    )
    ctx.setFillColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.92))
    ctx.fill(stemRect)

    let baseRect = CGRect(
        x: s * 0.34,
        y: stemRect.minY - s * 0.03,
        width: s * 0.32,
        height: s * 0.05
    )
    let basePath = CGPath(
        roundedRect: baseRect,
        cornerWidth: s * 0.025,
        cornerHeight: s * 0.025,
        transform: nil
    )
    ctx.addPath(basePath)
    ctx.fillPath()

    // Voice-wave arcs.
    let arcCenter = CGPoint(x: s * 0.5, y: s * 0.44)
    ctx.setLineCap(.round)
    ctx.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.82))
    ctx.setLineWidth(max(1.0, s * 0.03))
    for r in [s * 0.22, s * 0.30] {
        ctx.addArc(center: arcCenter, radius: r, startAngle: radians(112), endAngle: radians(248), clockwise: false)
        ctx.strokePath()
        ctx.addArc(center: arcCenter, radius: r, startAngle: radians(-68), endAngle: radians(68), clockwise: false)
        ctx.strokePath()
    }

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (px, filename) in variants {
    let rep = drawTile(side: CGFloat(px))
    guard let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write(Data("failed to encode \(filename)\n".utf8))
        exit(1)
    }
    let outURL = outDir.appendingPathComponent(filename)
    try png.write(to: outURL)
}
