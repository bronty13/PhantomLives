import Foundation

/// Locates the external command-line tools PurpleAttic drives. We never assume a tool is on
/// PATH (a Finder-launched .app has a minimal PATH); we probe the well-known Homebrew /
/// pipx locations explicitly, then fall back to `which`.
public enum Tooling {

    /// Common install locations for Homebrew (arm64 + Intel) and pipx user installs.
    private static let extraDirs = [
        "/opt/homebrew/bin",
        "/usr/local/bin",
        (NSHomeDirectory() as NSString).appendingPathComponent(".local/bin"),
        "/usr/bin",
        "/bin",
    ]

    /// Absolute path to a named tool, or nil if not found.
    public static func locate(_ name: String) -> String? {
        for dir in extraDirs {
            let candidate = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        // Fall back to PATH via /usr/bin/which.
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        p.arguments = [name]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        do {
            try p.run()
            p.waitUntilExit()
            guard p.terminationStatus == 0 else { return nil }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let path = String(data: data, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return path.isEmpty ? nil : path
        } catch {
            return nil
        }
    }

    public static var osxphotos: String? { locate("osxphotos") }
    public static var exiftool: String? { locate("exiftool") }
    public static var rsync: String? { locate("rsync") }
    /// restic drives the encrypted, verifiable off-site copy (replaces the Cryptomator vault).
    public static var restic: String? { locate("restic") }
    /// rclone is only needed for rclone-backed restic destinations (Dropbox/Proton/S3/…); a
    /// B2-only setup doesn't require it. Resolved here so adding such a destination is config-only.
    public static var rclone: String? { locate("rclone") }

    /// A readiness report for the `doctor` subcommand / GUI preflight.
    public struct Readiness: Sendable {
        public let osxphotos: String?
        public let exiftool: String?
        public let rsync: String?

        public var allPresent: Bool { osxphotos != nil && exiftool != nil && rsync != nil }
    }

    public static func readiness() -> Readiness {
        Readiness(osxphotos: osxphotos, exiftool: exiftool, rsync: rsync)
    }
}
