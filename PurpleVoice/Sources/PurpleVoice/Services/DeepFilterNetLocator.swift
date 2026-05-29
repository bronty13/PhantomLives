import Foundation

/// Finds the `deep-filter` Rust CLI for the optional DeepFilterNet
/// engine. Mirror of `FFmpegLocator` — same search-order pattern, same
/// `PURPLE_VOICE_*` env-override convention.
///
/// Install:    `cargo install deep_filter`  (note the underscore in
///             the crate name vs. the dash in the resulting binary)
/// Homepage:   https://github.com/Rikorose/DeepFilterNet
///
/// If this returns `nil`, the engine is effectively unavailable. The
/// UI shows an install hint in the Processing settings tab and the
/// ClipProcessor falls back to ffmpeg with a clearly-labelled error.
enum DeepFilterNetLocator {

    /// Search locations in priority order:
    /// 1. `PURPLE_VOICE_DEEPFILTER` env var (escape hatch for tests)
    /// 2. User-set override path (Settings → Advanced) — passed in
    ///    via the `override` parameter
    /// 3. `~/.cargo/bin/deep-filter` (default `cargo install` target)
    /// 4. `/opt/homebrew/bin/deep-filter` (Apple Silicon Homebrew —
    ///    no official tap today, but covers manual symlinks)
    /// 5. `/usr/local/bin/deep-filter` (Intel Homebrew)
    /// 6. PATH lookup via `/usr/bin/which`
    static func find(override: String? = nil,
                     environment: [String: String]? = nil,
                     fileManager: FileManager = .default) -> URL? {
        let env = environment ?? ProcessInfo.processInfo.environment

        if let envOverride = env["PURPLE_VOICE_DEEPFILTER"],
           !envOverride.isEmpty,
           fileManager.isExecutableFile(atPath: envOverride) {
            return URL(fileURLWithPath: envOverride)
        }

        if let override, !override.isEmpty,
           fileManager.isExecutableFile(atPath: override) {
            return URL(fileURLWithPath: override)
        }

        let home = NSHomeDirectory()
        let knownPaths = [
            "\(home)/.cargo/bin/deep-filter",
            "/opt/homebrew/bin/deep-filter",
            "/usr/local/bin/deep-filter",
            "/opt/local/bin/deep-filter"
        ]
        for p in knownPaths where fileManager.isExecutableFile(atPath: p) {
            return URL(fileURLWithPath: p)
        }

        if let viaWhich = whichLookup(name: "deep-filter", env: env) {
            return viaWhich
        }
        return nil
    }

    private static func whichLookup(name: String, env: [String: String]) -> URL? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        p.arguments = [name]
        var augmented = env
        let inheritedPath = env["PATH"] ?? ""
        let home = NSHomeDirectory()
        augmented["PATH"] = "\(inheritedPath):\(home)/.cargo/bin:/opt/homebrew/bin:/usr/local/bin:/opt/local/bin:/usr/bin:/bin"
        p.environment = augmented
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = Pipe()
        do {
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let raw = String(data: data, encoding: .utf8) ?? ""
            let path = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            return path.isEmpty ? nil : URL(fileURLWithPath: path)
        } catch {
            return nil
        }
    }
}
