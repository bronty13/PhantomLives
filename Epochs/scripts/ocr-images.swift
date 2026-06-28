#!/usr/bin/env swift
//
// ocr-images.swift — on-device OCR of a folder of images into one Markdown file,
// using Apple's Vision framework (.accurate + language correction). Zero install
// (Vision ships with macOS) and higher accuracy than Tesseract on clean scans.
//
// Reuses the approach from PurpleSpeak's OCRService.swift. This is a TOOL: it runs
// entirely on YOUR machine against YOUR own images. Point it at material you own
// (e.g. your own scanned pages) and send the Markdown wherever you like — your
// Obsidian vault, for instance. Nothing leaves the device; nothing is committed.
//
// Usage:
//   swift ocr-images.swift <image-or-dir> [more images/dirs...] <output.md>
//
// Example (the bundled rulebook scans -> a note in your vault):
//   swift Epochs/scripts/ocr-images.swift \
//     Epochs/src/renderer/public/rulebook \
//     ~/ObsidianVault/Games/HistoryOfTheWorld-Rulebook.md
//
import Foundation
import AppKit
import Vision

let IMAGE_EXTS: Set<String> = ["png", "jpg", "jpeg", "tiff", "tif", "heic", "gif", "bmp"]

func err(_ s: String) { FileHandle.standardError.write((s + "\n").data(using: .utf8)!) }

/// Collapse runs of blank lines / trailing spaces so the Markdown is tidy.
func tidy(_ s: String) -> String {
    let lines = s.split(separator: "\n", omittingEmptySubsequences: false)
        .map { $0.trimmingCharacters(in: .whitespaces) }
    var out: [String] = []
    var blanks = 0
    for l in lines {
        if l.isEmpty { blanks += 1; if blanks <= 1 { out.append("") } }
        else { blanks = 0; out.append(l) }
    }
    return out.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
}

/// OCR one image. Returns recognized text in Vision's natural (reading) order.
func recognize(_ url: URL) -> String {
    guard let img = NSImage(contentsOf: url),
          let cg = img.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
        err("  ! couldn't read \(url.lastPathComponent)")
        return ""
    }
    let request = VNRecognizeTextRequest()
    request.recognitionLevel = .accurate
    request.usesLanguageCorrection = true
    request.recognitionLanguages = ["en-US"]
    let handler = VNImageRequestHandler(cgImage: cg, options: [:])
    do { try handler.perform([request]) } catch {
        err("  ! OCR failed for \(url.lastPathComponent): \(error.localizedDescription)")
        return ""
    }
    guard let obs = request.results else { return "" }
    return tidy(obs.compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n"))
}

// ── args ─────────────────────────────────────────────────────────────────────
let args = Array(CommandLine.arguments.dropFirst())
if args.count < 2 || args.contains("--help") || args.contains("-h") {
    print("usage: swift ocr-images.swift <image-or-dir> [more...] <output.md>")
    exit(args.isEmpty ? 2 : 0)
}
let outPath = (args.last! as NSString).expandingTildeInPath
let inputs = args.dropLast()
let fm = FileManager.default

// expand dirs → image files, sorted naturally (page-01, page-02, …)
var files: [URL] = []
for a in inputs {
    let u = URL(fileURLWithPath: (a as NSString).expandingTildeInPath)
    var isDir: ObjCBool = false
    if fm.fileExists(atPath: u.path, isDirectory: &isDir), isDir.boolValue {
        let kids = (try? fm.contentsOfDirectory(at: u, includingPropertiesForKeys: nil)) ?? []
        files += kids.filter { IMAGE_EXTS.contains($0.pathExtension.lowercased()) }
    } else if IMAGE_EXTS.contains(u.pathExtension.lowercased()) {
        files.append(u)
    } else {
        err("  ? skipping (not an image / dir): \(a)")
    }
}
files.sort { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
guard !files.isEmpty else { err("no image files found"); exit(1) }

// ── OCR every page → one Markdown file ───────────────────────────────────────
var md = "# OCR transcription — \(files.count) pages\n\n"
md += "_On-device OCR via Apple Vision (.accurate). Personal reference; generated locally._\n"
for (i, f) in files.enumerated() {
    err("OCR \(i + 1)/\(files.count): \(f.lastPathComponent)")
    let text = recognize(f)
    md += "\n\n---\n\n## Page \(i + 1) · \(f.lastPathComponent)\n\n"
    md += text.isEmpty ? "_(no text recognized)_\n" : text + "\n"
}
do {
    try md.write(toFile: outPath, atomically: true, encoding: .utf8)
    print("✓ wrote \(files.count) pages → \(outPath)")
} catch {
    err("could not write \(outPath): \(error.localizedDescription)")
    exit(1)
}
