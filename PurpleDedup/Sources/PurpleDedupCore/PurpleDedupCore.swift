import Foundation

/// PurpleDedup version + identity constants. Build-time identifiers (CFBundleVersion etc.)
/// are derived from git in `build-app.sh`; this is the runtime fallback the CLI prints.
public enum PurpleDedup {
    public static let appName = "PurpleDedup"
    public static let bundleIdentifier = "com.bronty13.PurpleDedup"
    public static let coreVersion = "0.22.0"

    /// The folder under `~/Library/Application Support` where we stash the SQLite cache,
    /// scan sessions, and any other internal state.
    public static var supportDirectoryURL: URL {
        let lib = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return lib.appendingPathComponent(appName, isDirectory: true)
    }

    /// PhantomLives convention: user-visible output (exported reports, JSON dumps) defaults
    /// here. `~/Downloads/PurpleDedup/`.
    public static var defaultOutputDirectoryURL: URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        return downloads.appendingPathComponent(appName, isDirectory: true)
    }

    /// PhantomLives convention: backup archives go in a sibling folder with " backup" suffix.
    public static var defaultBackupDirectoryURL: URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
        return downloads.appendingPathComponent("\(appName) backup", isDirectory: true)
    }
}
