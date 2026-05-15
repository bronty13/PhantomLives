import Foundation

/// Canonical paths under `~/Library/Application Support/SlackSucker/`.
/// Created on demand so the first call from a fresh install doesn't fail.
/// This is where run history, presets, settings, and the channel cache
/// live — not where archives are written (those go to the user-visible
/// `~/Downloads/SlackSucker/` per the PhantomLives convention).
enum AppSupport {
    static let appName = "SlackSucker"

    static var directory: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Library/Application Support")
        let dir = base.appendingPathComponent(appName, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static var settingsURL:     URL { directory.appendingPathComponent("settings.json") }
    static var runHistoryURL:   URL { directory.appendingPathComponent("runs.json") }
    static var presetsURL:      URL { directory.appendingPathComponent("presets.json") }
    static var channelCacheDir: URL {
        let dir = directory.appendingPathComponent("channel-cache", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Default user-visible output root: `~/Downloads/SlackSucker/`. Per
    /// the PhantomLives convention (CLAUDE.md), created on demand.
    static var defaultOutputDir: URL {
        let downloads = FileManager.default
            .urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser
                .appendingPathComponent("Downloads")
        return downloads.appendingPathComponent(appName, isDirectory: true)
    }
}

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
