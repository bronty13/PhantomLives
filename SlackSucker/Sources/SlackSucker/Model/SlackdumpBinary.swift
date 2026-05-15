import Foundation

/// Resolves the bundled `slackdump` binary. The binary lives at
/// `SlackSucker.app/Contents/Resources/slackdump`, copied in by
/// `build-app.sh` from `$SLACKDUMP_BIN` or `which slackdump`.
///
/// We don't fall back to PATH at runtime — the bundled binary is the
/// only supported way to drive slackdump from the GUI. The exit-code
/// surface, flag set, and stdout shape are all pinned to whatever was
/// bundled at build time, so a stray PATH installation can't drift
/// behavior under us.
enum SlackdumpBinary {

    /// Path to the bundled binary, or nil when running outside a `.app`
    /// (e.g. `swift run`). Tests inject a mock path via the test-helper
    /// initializer below.
    static var bundledPath: String? {
        guard let url = Bundle.main.url(forResource: "slackdump", withExtension: nil)
        else { return nil }
        return url.path
    }

    /// One-time chmod +x. Idempotent — calling repeatedly on an already-
    /// executable file is a no-op. Failures are logged but non-fatal;
    /// the spawn will surface a clearer error if the bit really isn't set.
    static func ensureExecutable(at path: String) {
        let fm = FileManager.default
        if let attrs = try? fm.attributesOfItem(atPath: path),
           let posix = attrs[.posixPermissions] as? NSNumber,
           (posix.uint16Value & 0o111) != 0 {
            return
        }
        do {
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: path)
        } catch {
            NSLog("SlackSucker: chmod +x on slackdump failed — \(error.localizedDescription)")
        }
    }

    /// Resolve + prepare the binary for use. Returns nil when the bundle
    /// doesn't contain a slackdump resource (e.g. dev `swift run`).
    static func resolvedPath() -> String? {
        guard let path = bundledPath else { return nil }
        ensureExecutable(at: path)
        return path
    }

    /// Bundle path classification for `BinaryResolutionTests`. Pure: takes
    /// a probe URL rather than reading the live `Bundle.main`, so tests can
    /// point at a temp dir.
    static func resolveFromBundle(_ bundle: Bundle) -> String? {
        bundle.url(forResource: "slackdump", withExtension: nil)?.path
    }
}
