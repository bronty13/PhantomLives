import Foundation

/// Canonical on-disk locations for PurpleSpeak, per the PhantomLives
/// conventions:
///   • user-visible output  → ~/Downloads/PurpleSpeak/
///   • backups              → ~/Downloads/PurpleSpeak backup/
///   • private app state    → ~/Library/Application Support/PurpleSpeak/
/// Every accessor creates its directory on demand (`mkdir -p` semantics).
enum SupportPaths {
    static let appName = "PurpleSpeak"

    /// ~/Library/Application Support/PurpleSpeak/ — library index, settings,
    /// cached document text, downloaded Whisper models.
    static var supportDirectory: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!.appendingPathComponent(appName, isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    /// Where extracted document text + per-document metadata live.
    static var documentsStore: URL {
        let dir = supportDirectory.appendingPathComponent("documents", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Downloaded Whisper GGML models.
    static var modelsDirectory: URL {
        let dir = supportDirectory.appendingPathComponent("models", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// settings.json
    static var settingsFile: URL {
        supportDirectory.appendingPathComponent("settings.json")
    }

    /// library.json — the document index.
    static var libraryFile: URL {
        supportDirectory.appendingPathComponent("library.json")
    }

    /// Default user-visible output root, overridable in Settings.
    /// ~/Downloads/PurpleSpeak/
    static var defaultOutputDirectory: URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        return downloads.appendingPathComponent(appName, isDirectory: true)
    }

    /// Default backup directory. ~/Downloads/PurpleSpeak backup/
    static var defaultBackupDirectory: URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Downloads")
        return downloads.appendingPathComponent("\(appName) backup", isDirectory: true)
    }

    /// Expand a stored "~/..."-style path into an absolute URL.
    static func expand(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
    }
}
