#!/usr/bin/env swift
//
// generate-icon.swift — render PurpleArchive's app icon into an .iconset dir.
// Usage: swift generate-icon.swift <output.iconset>
//
// Draws a purple gradient rounded-rect with a stylized archive box (a drawer
// with a pull) — programmatic so there are no binary assets to keep in sync.

import AppKit

let outDir = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.iconset"
try? FileManager.default.createDirectory(atPath: outDir, withIntermediateDirectories: true)

func render(_ px: Int) -> Data {
    let size = CGFloat(px)
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()
    let ctx = NSGraphicsContext.current!.cgContext

    // Rounded-rect background with a purple vertical gradient.
    let inset = size * 0.06
    let rect = CGRect(x: inset, y: inset, width: size - 2*inset, height: size - 2*inset)
    let radius = size * 0.22
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.addPath(path); ctx.clip()
    let colors = [NSColor(calibratedRed: 0.55, green: 0.30, blue: 0.95, alpha: 1).cgColor,
                  NSColor(calibratedRed: 0.36, green: 0.16, blue: 0.78, alpha: 1).cgColor]
    let grad = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                          colors: colors as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: size), end: CGPoint(x: 0, y: 0), options: [])

    // Archive box: a white rounded rectangle with a horizontal lid line + pull.
    ctx.resetClip()
    let boxW = size * 0.52, boxH = size * 0.44
    let boxX = (size - boxW) / 2, boxY = (size - boxH) / 2 - size * 0.02
    let boxRect = CGRect(x: boxX, y: boxY, width: boxW, height: boxH)
    let boxPath = CGPath(roundedRect: boxRect, cornerWidth: size*0.04, cornerHeight: size*0.04, transform: nil)
    ctx.setFillColor(NSColor.white.cgColor)
    ctx.addPath(boxPath); ctx.fillPath()

    // Lid line.
    let lidY = boxY + boxH * 0.66
    ctx.setStrokeColor(NSColor(calibratedRed: 0.36, green: 0.16, blue: 0.78, alpha: 1).cgColor)
    ctx.setLineWidth(max(1, size * 0.018))
    ctx.move(to: CGPoint(x: boxX, y: lidY))
    ctx.addLine(to: CGPoint(x: boxX + boxW, y: lidY))
    ctx.strokePath()

    // Pull (a short bar) centered on the lid line.
    let pullW = boxW * 0.26, pullH = boxH * 0.12
    let pull = CGRect(x: size/2 - pullW/2, y: lidY - pullH/2, width: pullW, height: pullH)
    ctx.setFillColor(NSColor(calibratedRed: 0.55, green: 0.30, blue: 0.95, alpha: 1).cgColor)
    ctx.addPath(CGPath(roundedRect: pull, cornerWidth: pullH/2, cornerHeight: pullH/2, transform: nil))
    ctx.fillPath()

    image.unlockFocus()
    let tiff = image.tiffRepresentation!
    let rep = NSBitmapImageRep(data: tiff)!
    return rep.representation(using: .png, properties: [:])!
}

let specs: [(name: String, px: Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for spec in specs {
    let data = render(spec.px)
    try! data.write(to: URL(fileURLWithPath: "\(outDir)/\(spec.name).png"))
}
print("Wrote \(specs.count) icon sizes to \(outDir)")
