#!/usr/bin/env swift
//
// Emits SHORTCUTS.md from Sources/PurpleReel/Help/Shortcuts.swift.
//
// Usage:
//   swift Scripts/generate-shortcuts-md.swift [output-path]
//
// Default output: <repo-root>/SHORTCUTS.md
//
// Reads the canonical Shortcuts.swift source file as text and parses
// the `.init(...)` lines inside `Shortcuts.all`. This keeps the doc in
// lock-step with the in-app cheat sheet without duplicating the data.
//
// The parser tolerates trailing commas, multi-line entries, and
// `source: …` labelled arguments. New shortcut groups picked up
// automatically from `ShortcutGroup`.

import Foundation

// MARK: - Locate inputs

let fm = FileManager.default
let scriptURL = URL(fileURLWithPath: CommandLine.arguments[0]).resolvingSymlinksInPath()
let repoRoot = scriptURL.deletingLastPathComponent().deletingLastPathComponent()
let sourceFile = repoRoot
    .appendingPathComponent("Sources/PurpleReel/Help/Shortcuts.swift")
let outputPath: URL = {
    if CommandLine.arguments.count > 1 {
        return URL(fileURLWithPath: CommandLine.arguments[1])
    }
    return repoRoot.appendingPathComponent("SHORTCUTS.md")
}()

guard let raw = try? String(contentsOf: sourceFile, encoding: .utf8) else {
    fputs("error: could not read \(sourceFile.path)\n", stderr)
    exit(1)
}

// MARK: - Parse

struct Entry {
    let group: String
    let combo: String
    let action: String
}

// Walk the file line-by-line, looking for `.init(.<group>, "<combo>",
// "<action>"…)`. Multi-line entries are joined first so the regex
// only ever sees a single line. This is a tiny purpose-built parser
// — full Swift parsing would be overkill.
let collapsed: String = {
    // Join continuation lines that end with an open paren or comma so
    // each `.init(...)` lives on one line.
    var out = ""
    var paren = 0
    for ch in raw {
        if ch == "(" { paren += 1 }
        if ch == ")" { paren -= 1 }
        if ch == "\n" && paren > 0 {
            out.append(" ")
        } else {
            out.append(ch)
        }
    }
    return out
}()

let pattern = #"\.init\(\.([a-zA-Z]+),\s*"([^"]*)"\s*,\s*"([^"]*)""#
let regex = try! NSRegularExpression(pattern: pattern)

var entries: [Entry] = []
collapsed.enumerateLines { line, _ in
    let range = NSRange(line.startIndex..<line.endIndex, in: line)
    regex.enumerateMatches(in: line, options: [], range: range) { match, _, _ in
        guard let m = match,
              let groupRange  = Range(m.range(at: 1), in: line),
              let comboRange  = Range(m.range(at: 2), in: line),
              let actionRange = Range(m.range(at: 3), in: line) else { return }
        entries.append(Entry(
            group: String(line[groupRange]),
            combo: String(line[comboRange]),
            action: String(line[actionRange])
        ))
    }
}

guard !entries.isEmpty else {
    fputs("error: no shortcut entries parsed from \(sourceFile.lastPathComponent)\n", stderr)
    exit(2)
}

// MARK: - Group + render

// Group display name lookup. Mirrors `ShortcutGroup` raw values.
let groupOrder: [(token: String, display: String)] = [
    ("browser",  "Browser"),
    ("player",   "Player"),
    ("logging",  "Logging & Metadata"),
    ("convert",  "Convert / Send"),
    ("view",     "View"),
    ("window",   "Window"),
]

var md = ""
md += "# PurpleReel Keyboard Shortcuts\n\n"
md += "Generated from `Sources/PurpleReel/Help/Shortcuts.swift` — do "
md += "not edit by hand. Run `swift Scripts/generate-shortcuts-md.swift` "
md += "to refresh after changing the source file. The in-app cheat "
md += "sheet (Help → Keyboard Shortcuts…) reads from the same data.\n\n"

md += "**Tip:** All combos work whether the player has focus or the "
md += "browser does. macOS standard shortcuts (⌘W close window, ⌘Q "
md += "quit, ⌘, settings) are not duplicated here.\n\n"

for (token, display) in groupOrder {
    let groupEntries = entries.filter { $0.group == token }
    if groupEntries.isEmpty { continue }
    md += "## \(display)\n\n"
    md += "| Shortcut | Action |\n"
    md += "|---|---|\n"
    for e in groupEntries {
        // Escape pipe characters in case anyone embeds them in the
        // action text later. Combos are already safe.
        let safeAction = e.action.replacingOccurrences(of: "|", with: "\\|")
        md += "| `\(e.combo)` | \(safeAction) |\n"
    }
    md += "\n"
}

md += "---\n\n"
md += "Total: **\(entries.count)** documented shortcuts.\n"

// MARK: - Write

do {
    try md.write(to: outputPath, atomically: true, encoding: .utf8)
    print("Wrote \(outputPath.path) (\(entries.count) shortcuts)")
} catch {
    fputs("error: could not write \(outputPath.path): \(error)\n", stderr)
    exit(3)
}
