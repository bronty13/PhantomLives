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

    /// Replace illegal POSIX path characters and trim leading/trailing dots/
    /// spaces. Empty input becomes `Untitled`.
    static func sanitize(_ s: String) -> String {
        let collapsed = s.trimmingCharacters(in: .whitespacesAndNewlines)
        if collapsed.isEmpty { return "Untitled" }
        let bad = CharacterSet(charactersIn: "/:\\?<>|\"*\0")
        let cleaned = collapsed
            .components(separatedBy: bad)
            .joined(separator: "-")
            .trimmingCharacters(in: CharacterSet(charactersIn: ". "))
        return cleaned.isEmpty ? "Untitled" : cleaned
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
