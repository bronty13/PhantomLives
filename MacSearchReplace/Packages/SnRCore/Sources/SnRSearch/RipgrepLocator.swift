import Foundation

/// Locate the bundled `ripgrep` binary. Search order:
///   1. Process env override: `SNR_RIPGREP_PATH`.
///   2. Same directory as the running executable (`.app/Contents/MacOS/rg`).
///   3. /usr/local/bin/rg, /opt/homebrew/bin/rg.
///   4. PATH lookup via `which`.
public enum RipgrepLocator {

    public static func locate() -> URL? {
        if let env = ProcessInfo.processInfo.environment["SNR_RIPGREP_PATH"],
           FileManager.default.isExecutableFile(atPath: env) {
            return URL(fileURLWithPath: env)
        }

        let exe = Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0])
        let sibling = exe.deletingLastPathComponent().appendingPathComponent("rg")
        if FileManager.default.isExecutableFile(atPath: sibling.path) {
            return sibling
        }

        for candidate in ["/usr/local/bin/rg", "/opt/homebrew/bin/rg", "/usr/bin/rg"] {
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }

        // PATH lookup
        let task = Process()
        task.launchPath = "/usr/bin/env"
        task.arguments = ["which", "rg"]
        let pipe = Pipe()
        task.standardOutput = pipe
        task.standardError = Pipe()
        try? task.run()
        task.waitUntilExit()
        if task.terminationStatus == 0 {
            let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            let path = out.trimmingCharacters(in: .whitespacesAndNewlines)
            if !path.isEmpty {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }
}
