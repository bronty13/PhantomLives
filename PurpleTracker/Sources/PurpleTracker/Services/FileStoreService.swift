import Foundation
import AppKit

/// Resolve and act on the two file-store paths attached to a Matter. Templates
/// live in `AppSettings.fileStorePrimaryTemplate` / `…SecondaryTemplate` with
/// `{year}`, `{date}`, and `{title}` substitutions. The Matter row stores its
/// resolved-at-create-time paths so a later template change doesn't move
/// existing folders out from under the user.
enum FileStoreService {

    /// Substitute template placeholders. `{date}` is the Matter ID's date prefix
    /// when a Matter ID is available, falling back to today. Title is filesystem-
    /// sanitized.
    static func render(template: String, title: String, date: Date = Date()) -> String {
        let yf = DateFormatter()
        yf.dateFormat = "yyyy"
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd"
        let safeTitle = sanitize(title)
        return template
            .replacingOccurrences(of: "{year}", with: yf.string(from: date))
            .replacingOccurrences(of: "{date}", with: df.string(from: date))
            .replacingOccurrences(of: "{title}", with: safeTitle)
    }

    /// Same as `render` but using the date encoded in a Matter ID. Falls back
    /// to today if the Matter ID is malformed.
    static func render(template: String, title: String, matterId: String) -> String {
        let date = MatterIDService.dateFormatter.date(from: String(matterId.prefix(10))) ?? Date()
        return render(template: template, title: title, date: date)
    }

    /// Sanitize a string for use as a single path component. Strips characters
    /// that aren't allowed on macOS or that cause trouble on the SMB / OneDrive
    /// / Windows surfaces this app routinely syncs to:
    ///
    /// - control chars (`0x00`–`0x1F`, `0x7F`)
    /// - path separators and reserved chars: `/ \ : ? < > | " *`
    /// - leading/trailing dots and whitespace (Finder hides leading dots; Windows
    ///   trims trailing dots & spaces silently and the names then collide)
    /// - reserved Windows device names (`CON`, `PRN`, `AUX`, `NUL`, `COM1…9`,
    ///   `LPT1…9`) — get a trailing underscore so they round-trip on OneDrive
    ///
    /// Empty input becomes `Untitled`. The result never exceeds 200 bytes
    /// (well under HFS+/APFS' 255-byte filename limit even with multibyte UTF-8).
    static func sanitize(_ s: String) -> String {
        let trimmed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return "Untitled" }

        // Disallowed: path separators, Windows-reserved chars, NUL, and any
        // control character (C0 + DEL). We map all of them to "-" rather than
        // dropping them, so two distinct titles can't accidentally collide.
        var bad = CharacterSet(charactersIn: "/\\:?<>|\"*\0")
        bad.formUnion(.controlCharacters)

        let cleaned = trimmed
            .components(separatedBy: bad)
            .joined(separator: "-")
            // Collapse runs of "-" so we don't end up with e.g. "a---b".
            .replacingOccurrences(of: #"-{2,}"#, with: "-", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet(charactersIn: ". -"))

        if cleaned.isEmpty { return "Untitled" }

        // Avoid Windows-reserved device names (case-insensitive, with or without
        // an extension). Append "_" if the bare stem matches.
        let reserved: Set<String> = [
            "con", "prn", "aux", "nul",
            "com1", "com2", "com3", "com4", "com5", "com6", "com7", "com8", "com9",
            "lpt1", "lpt2", "lpt3", "lpt4", "lpt5", "lpt6", "lpt7", "lpt8", "lpt9"
        ]
        let stem = (cleaned as NSString).deletingPathExtension.lowercased()
        let final = reserved.contains(stem) ? cleaned + "_" : cleaned

        // Cap at 200 bytes UTF-8 so we never blow the 255-byte filename limit.
        return Self.truncatedUTF8(final, maxBytes: 200)
    }

    private static func truncatedUTF8(_ s: String, maxBytes: Int) -> String {
        guard s.utf8.count > maxBytes else { return s }
        var out = ""
        var bytes = 0
        for ch in s {
            let chBytes = String(ch).utf8.count
            if bytes + chBytes > maxBytes { break }
            out.append(ch)
            bytes += chBytes
        }
        return out.trimmingCharacters(in: CharacterSet(charactersIn: ". -"))
    }

    /// Expand `~` and create the directory. Returns the resolved URL.
    @discardableResult
    static func createDirectory(at path: String) throws -> URL {
        let url = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Reveal the path in Finder. Creates a parent directory if needed when
    /// the leaf doesn't yet exist (so "Reveal" never leaves the user staring
    /// at nothing).
    static func reveal(path: String) {
        let expanded = (path as NSString).expandingTildeInPath
        let url = URL(fileURLWithPath: expanded)
        if FileManager.default.fileExists(atPath: url.path) {
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } else {
            // Reveal the deepest existing parent.
            var probe = url.deletingLastPathComponent()
            while !FileManager.default.fileExists(atPath: probe.path)
                  && probe.path != "/" {
                probe.deleteLastPathComponent()
            }
            NSWorkspace.shared.open(probe)
        }
    }
}
