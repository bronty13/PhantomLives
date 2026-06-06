import Foundation

/// Sanitize entry names so an archive made on a Mac extracts cleanly on Windows.
/// Windows forbids `\ / : * ? " < > |`, reserved device names (CON, PRN, NUL,
/// COM1–9, LPT1–9), and trailing dots/spaces — names that are perfectly legal on
/// macOS. This is the "create for Windows" safety net competitors lack.
public enum WindowsSafeNamer {

    static let reservedChars: Set<Character> = ["<", ">", ":", "\"", "\\", "|", "?", "*"]
    static let reservedNames: Set<String> = {
        var s: Set<String> = ["CON", "PRN", "AUX", "NUL"]
        for i in 1...9 { s.insert("COM\(i)"); s.insert("LPT\(i)") }
        return s
    }()

    /// Returns true if `name` (a single path component) is already Windows-safe.
    public static func isSafe(_ name: String) -> Bool {
        sanitizeComponent(name) == name
    }

    /// Sanitize one path component.
    public static func sanitizeComponent(_ name: String) -> String {
        guard !name.isEmpty else { return name }
        // Replace reserved + control characters with '_'.
        var cleaned = String(name.map { ch in
            (reservedChars.contains(ch) || ch.asciiValue.map { $0 < 0x20 } == true) ? "_" : ch
        })
        // Trim trailing dots/spaces (Windows silently strips them → collisions).
        while let last = cleaned.last, last == "." || last == " " {
            cleaned.removeLast()
        }
        if cleaned.isEmpty { cleaned = "_" }
        // Reserved device names (case-insensitive, with or without extension).
        let stem = (cleaned as NSString).deletingPathExtension.uppercased()
        if reservedNames.contains(stem) {
            cleaned = "_" + cleaned
        }
        return cleaned
    }

    /// Sanitize a full POSIX-style relative path component-by-component.
    public static func sanitizePath(_ path: String) -> String {
        path.split(separator: "/", omittingEmptySubsequences: false)
            .map { $0.isEmpty ? "" : sanitizeComponent(String($0)) }
            .joined(separator: "/")
    }
}
