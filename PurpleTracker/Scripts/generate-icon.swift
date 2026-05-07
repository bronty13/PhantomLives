#!/usr/bin/env swift
import AppKit

// Generates a simple "PT" purple-on-white app icon into the iconset directory
// passed as the first argument. Produces every macOS-required size in both 1x
// and 2x. Lightweight stand-in until a hand-designed icon is added.

guard CommandLine.arguments.count >= 2 else {
    FileHandle.standardError.write("Usage: generate-icon.swift <iconset-dir>\n".data(using: .utf8)!)
    exit(2)
}
let iconsetDir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: iconsetDir, withIntermediateDirectories: true)

let sizes: [(label: String, px: Int)] = [
    ("16x16",      16),  ("16x16@2x",   32),
    ("32x32",      32),  ("32x32@2x",   64),
    ("128x128",   128),  ("128x128@2x", 256),
    ("256x256",   256),  ("256x256@2x", 512),
    ("512x512",   512),  ("512x512@2x", 1024),
]

let purple = NSColor(srgbRed: 0.529, green: 0.337, blue: 0.737, alpha: 1)
let white  = NSColor.white

for (label, px) in sizes {
    let img = NSImage(size: NSSize(width: px, height: px))
    img.lockFocus()
    let r = NSRect(x: 0, y: 0, width: px, height: px)
    let radius = CGFloat(px) * 0.22
    let path = NSBezierPath(roundedRect: r, xRadius: radius, yRadius: radius)
    purple.setFill()
    path.fill()

    let text = "PT" as NSString
    let fontSize = CGFloat(px) * 0.46
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: fontSize, weight: .heavy),
        .foregroundColor: white,
    ]
    let size = text.size(withAttributes: attrs)
    let pt = NSPoint(x: (CGFloat(px) - size.width) / 2,
                     y: (CGFloat(px) - size.height) / 2)
    text.draw(at: pt, withAttributes: attrs)
    img.unlockFocus()

    guard let tiff = img.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("Failed to render \(label)\n".data(using: .utf8)!)
        exit(1)
    }
    let outURL = URL(fileURLWithPath: iconsetDir).appendingPathComponent("icon_\(label).png")
    try png.write(to: outURL)
}
