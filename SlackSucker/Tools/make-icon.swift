#!/usr/bin/env swift
//
// make-icon.swift — generates SlackSucker.app's AppIcon.icns.
//
// Renders a deep-purple squircle background with an octopus emoji as
// the central subject, surrounded by four white hash glyphs (Slack's
// channel marker). The squid metaphor follows the app name; the
// hashes signal "what's being grabbed."
//
// Outputs Resources/AppIcon.icns by way of a temporary .iconset and
// `iconutil`. Re-run any time you want to refresh the icon — the .icns
// is what `build-app.sh` copies into the bundle.
//
//   swift Tools/make-icon.swift
//
import AppKit
import CoreImage

let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resourcesDir = projectRoot.appendingPathComponent("Resources", isDirectory: true)
try? FileManager.default.createDirectory(at: resourcesDir, withIntermediateDirectories: true)
let iconsetDir = projectRoot.appendingPathComponent(".AppIcon.iconset", isDirectory: true)
try? FileManager.default.removeItem(at: iconsetDir)
try FileManager.default.createDirectory(at: iconsetDir, withIntermediateDirectories: true)

// (px, filename). macOS's .icns format wants every (size, @2x) pair.
let renders: [(Int, String)] = [
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

/// Render one PNG at the requested square size, drawing directly into
/// an NSBitmapImageRep. Avoids the NSImage.lockFocus path which has
/// edge cases at very small sizes (16×16 fails to finalize the
/// underlying CGImageDestination on macOS 14+).
func renderIcon(size: CGFloat, to fileURL: URL) {
    let px = Int(size)
    guard let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: px, pixelsHigh: px,
        bitsPerSample: 8, samplesPerPixel: 4,
        hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0
    ), let nsCtx = NSGraphicsContext(bitmapImageRep: rep) else {
        FileHandle.standardError.write("alloc rep failed at \(px)\n".data(using: .utf8)!)
        exit(1)
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = nsCtx
    defer { NSGraphicsContext.restoreGraphicsState() }
    let ctx = nsCtx.cgContext

    // ── 1. Squircle clip (macOS uses ~22.5% corner radius)
    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let radius = size * 0.225
    let clip = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    ctx.saveGState()
    ctx.addPath(clip)
    ctx.clip()

    // ── 2. Deep purple diagonal gradient (top-left → bottom-right)
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    let bgColors = [
        NSColor(red: 0.18, green: 0.04, blue: 0.42, alpha: 1.0).cgColor,
        NSColor(red: 0.48, green: 0.18, blue: 0.78, alpha: 1.0).cgColor,
    ] as CFArray
    let gradient = CGGradient(colorsSpace: colorSpace, colors: bgColors,
                              locations: [0.0, 1.0])!
    ctx.drawLinearGradient(gradient,
                           start: CGPoint(x: 0, y: size),
                           end: CGPoint(x: size, y: 0),
                           options: [])

    // ── 3. Subtle radial highlight in the top-left for depth
    let highlightColors = [
        NSColor(white: 1.0, alpha: 0.18).cgColor,
        NSColor(white: 1.0, alpha: 0.0).cgColor,
    ] as CFArray
    let highlight = CGGradient(colorsSpace: colorSpace, colors: highlightColors,
                               locations: [0.0, 1.0])!
    ctx.drawRadialGradient(highlight,
                           startCenter: CGPoint(x: size * 0.25, y: size * 0.78),
                           startRadius: 0,
                           endCenter: CGPoint(x: size * 0.25, y: size * 0.78),
                           endRadius: size * 0.6,
                           options: [])

    // ── 4. Hash glyphs only show at ≥64 px — anything smaller and they
    // blur into noise. The squircle + emoji read fine on their own.
    if size >= 64 {
        let hashSize = size * 0.18
        let hashFont = NSFont.systemFont(ofSize: hashSize, weight: .heavy)
        let hashAttr: [NSAttributedString.Key: Any] = [
            .font: hashFont,
            .foregroundColor: NSColor(white: 1.0, alpha: 0.85),
        ]
        let hashPositions: [(CGFloat, CGFloat)] = [
            (size * 0.20, size * 0.22),
            (size * 0.80, size * 0.22),
            (size * 0.13, size * 0.62),
            (size * 0.87, size * 0.62),
        ]
        for (cx, cy) in hashPositions {
            let hashStr = NSAttributedString(string: "#", attributes: hashAttr)
            let sz = hashStr.size()
            let r = NSRect(x: cx - sz.width / 2, y: cy - sz.height / 2,
                           width: sz.width, height: sz.height)
            hashStr.draw(in: r)
        }
    }

    // ── 5. Squid centre subject. AppleColorEmoji renders 🐙 in colour
    // when we use any system font and let the text engine fall back.
    let emojiScale: CGFloat = size <= 32 ? 0.86 : 0.72
    let emojiSize = size * emojiScale
    let emojiFont = NSFont.systemFont(ofSize: emojiSize)
    var emojiAttr: [NSAttributedString.Key: Any] = [.font: emojiFont]
    // Skip the shadow at tiny sizes — it just smears the alpha channel
    // and reads as muddy edges, not depth.
    if size >= 64 {
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(0.45)
        shadow.shadowBlurRadius = size * 0.04
        shadow.shadowOffset = NSSize(width: 0, height: -size * 0.015)
        emojiAttr[.shadow] = shadow
    }
    let emoji = NSAttributedString(string: "\u{1F419}", attributes: emojiAttr)
    let eSize = emoji.size()
    let eRect = NSRect(x: (size - eSize.width) / 2,
                       y: (size - eSize.height) / 2 - size * 0.02,
                       width: eSize.width, height: eSize.height)
    emoji.draw(in: eRect)

    ctx.restoreGState()
    nsCtx.flushGraphics()

    // ── 6. Encode + write PNG
    guard let png = rep.representation(using: .png, properties: [:]) else {
        FileHandle.standardError.write("Failed to encode PNG at \(px)\n".data(using: .utf8)!)
        exit(1)
    }
    do {
        try png.write(to: fileURL)
    } catch {
        FileHandle.standardError.write("Write failed: \(error)\n".data(using: .utf8)!)
        exit(1)
    }
}

for (pixels, name) in renders {
    let outURL = iconsetDir.appendingPathComponent(name)
    renderIcon(size: CGFloat(pixels), to: outURL)
    print("rendered \(pixels)×\(pixels) → \(name)")
}

// ── 7. iconutil to .icns
let icnsURL = resourcesDir.appendingPathComponent("AppIcon.icns")
try? FileManager.default.removeItem(at: icnsURL)
let proc = Process()
proc.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
proc.arguments = ["-c", "icns", iconsetDir.path, "-o", icnsURL.path]
try proc.run()
proc.waitUntilExit()
guard proc.terminationStatus == 0 else {
    FileHandle.standardError.write("iconutil failed with status \(proc.terminationStatus)\n".data(using: .utf8)!)
    exit(1)
}
print("wrote \(icnsURL.path)")

// Clean up the temp iconset — the .icns is the artifact we keep.
try? FileManager.default.removeItem(at: iconsetDir)
