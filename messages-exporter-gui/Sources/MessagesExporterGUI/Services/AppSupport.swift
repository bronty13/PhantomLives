import Foundation

/// Canonical paths under `~/Library/Application Support/MessagesExporterGUI/`.
/// Created on demand so the first call from a fresh install doesn't fail.
/// This is where the run-history JSON, preset JSON, and backup metadata
/// live — *not* where exports are written (those go to the user-visible
/// `~/Downloads/messages-exporter-gui/` per the PhantomLives convention).
enum AppSupport {
    static let appName = "MessagesExporterGUI"

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent(appName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var runHistoryURL: URL { directory.appendingPathComponent("runs.json") }
    static var presetsURL:    URL { directory.appendingPathComponent("presets.json") }
}

/// Formatter used for run/preset timestamps and "n minutes ago" hints in
/// the sidebar. ISO-8601 with seconds, en_US_POSIX, local TZ — matches
/// what the rest of PhantomLives uses for timestamped filenames so the
/// run history can be eyeballed against the run folder names without a
/// mental conversion.
enum RelativeTime {
    /// "now" / "4h ago" / "yesterday" / "Apr 21" — short, sidebar-friendly.
    static func short(_ date: Date, now: Date = Date()) -> String {
        let interval = now.timeIntervalSince(date)
        if interval < 60                { return "now" }
        if interval < 3600              { return "\(Int(interval / 60))m ago" }
        if interval < 86400             { return "\(Int(interval / 3600))h ago" }
        if interval < 86400 * 2         { return "yesterday" }
        if interval < 86400 * 7 {
            let days = Int(interval / 86400)
            return "\(days)d ago"
        }
        let f = DateFormatter()
        f.dateFormat = "MMM d"
        return f.string(from: date)
    }
}
