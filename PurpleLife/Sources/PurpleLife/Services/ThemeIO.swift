import Foundation

/// Pure-function JSON encode / decode for `UserTheme`. The UI surface
/// (NSSavePanel / NSOpenPanel pickers) is kept in the views that call
/// these helpers — this service is unit-testable without AppKit.
///
/// File format is just the existing `UserTheme` Codable shape. No
/// envelope, no version field — the lenient `init(from:)` on `UserTheme`
/// + the defensive `materialised` accessor cover the realistic failure
/// modes (corrupt hex, missing keys from a future format that drops a
/// slot, etc.) without a custom migration step.
enum ThemeIO {

    /// Suggested file extension. `.purplelifetheme.json` — the `.json`
    /// suffix means any JSON tool can open it; the `.purplelifetheme`
    /// segment makes it greppable and prepares the ground for a future
    /// UTType registration (when we want Finder to know the icon).
    static let fileExtension = "purplelifetheme.json"

    /// Sanitize a theme name into a filesystem-safe basename. Strips
    /// path separators (`/`, `\`), control characters, and trims leading
    /// dots so the result never produces a hidden file or escapes its
    /// parent directory. Empty / all-illegal names fall back to "theme".
    static func sanitizedFilename(for themeName: String) -> String {
        let illegal = CharacterSet(charactersIn: "/\\:*?\"<>|\u{0000}")
            .union(.controlCharacters)
        let cleaned = themeName
            .components(separatedBy: illegal)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "."))
        return cleaned.isEmpty ? "theme" : cleaned
    }

    /// Default filename for a theme: `<sanitized-name>.<fileExtension>`.
    static func defaultFilename(for theme: UserTheme) -> String {
        "\(sanitizedFilename(for: theme.name)).\(fileExtension)"
    }

    /// Pretty-printed JSON. Sorted keys so diffs between exports of the
    /// same theme are stable — useful when a user is iterating on a
    /// palette and wants to see what actually changed between saves.
    static func encode(_ theme: UserTheme) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(theme)
    }

    /// Decode a UserTheme from a JSON file. Returns the decoded theme
    /// with a **fresh UUID** so re-importing the same file (or a file
    /// shared from another Mac) doesn't collide with an existing theme's
    /// id. The original `basedOn` and `createdAt` metadata are preserved
    /// verbatim — they document provenance, not identity.
    static func decode(from data: Data) throws -> UserTheme {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var theme = try decoder.decode(UserTheme.self, from: data)
        theme.id = UUID()
        return theme
    }

    /// Convenience: encode + write atomically.
    static func write(_ theme: UserTheme, to url: URL) throws {
        let data = try encode(theme)
        try data.write(to: url, options: .atomic)
    }

    /// Convenience: read + decode (with fresh UUID).
    static func read(from url: URL) throws -> UserTheme {
        let data = try Data(contentsOf: url)
        return try decode(from: data)
    }
}
