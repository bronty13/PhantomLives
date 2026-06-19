import Foundation

/// Appends chat lines to plain-text logs under
/// `~/Downloads/Ircle/Logs/<network>/<target>.log` (per the repo default-output
/// convention). Off by default; never throws. One file per conversation.
@MainActor
final class LogService {
    static let shared = LogService()

    /// Mirrors `settings.loggingEnabled`, kept in sync by the model.
    var enabled = false
    /// Where logs are written. Overridable for tests.
    var directory: URL = LogService.defaultDirectory

    static var defaultDirectory: URL {
        SettingsStore.downloadsDirectory.appendingPathComponent("Logs", isDirectory: true)
    }

    /// Append one already-formatted line for `(network, target)`, timestamped.
    /// No-ops unless logging is enabled.
    func log(network: String, target: String, line: String) {
        guard enabled else { return }
        write(network: network, target: target, line: line)
    }

    /// The same write, ungated — used by tests and by `log(...)` once enabled.
    func write(network: String, target: String, line: String) {
        let url = fileURL(network: network, target: target)
        let entry = "[\(Self.timestamp())] \(line)\n"
        guard let data = entry.data(using: .utf8) else { return }
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(),
                                withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
        } else {
            try? data.write(to: url, options: .atomic)   // first write creates the file
        }
    }

    /// Path of the log file for a conversation.
    func fileURL(network: String, target: String) -> URL {
        directory.appendingPathComponent(Self.safe(network), isDirectory: true)
                 .appendingPathComponent(Self.safe(target) + ".log")
    }

    /// Sanitize a network/target name into a safe single path component:
    /// path separators, colons, and control characters become `_`.
    static func safe(_ s: String) -> String {
        var bad = CharacterSet(charactersIn: "/\\:")
        bad.formUnion(.controlCharacters)
        let joined = s.components(separatedBy: bad).joined(separator: "_")
        let trimmed = joined.trimmingCharacters(in: .whitespacesAndNewlines)
        // Never let a name escape the logs dir or hide the file.
        if trimmed.isEmpty || trimmed == "." || trimmed == ".." { return "_" }
        return trimmed
    }

    private static func timestamp() -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f.string(from: Date())
    }
}
