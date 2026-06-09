import Foundation

/// Detailed, append-only logging so a failed or surprising run is always diagnosable after
/// the fact. Machine-oriented logs live under `~/Library/Logs/PurpleAttic/` (per the
/// PhantomLives convention that caches/logs go under Library, not Downloads). A separate
/// human-readable run report is written to `~/Downloads/PurpleAttic/` by the engine.
///
/// Thread-safe via a serial queue; never throws (logging must not be able to fail a run).
public final class AtticLogger: @unchecked Sendable {

    public enum Level: String, Sendable {
        case debug = "DEBUG"
        case info  = "INFO "
        case warn  = "WARN "
        case error = "ERROR"
    }

    private let queue = DispatchQueue(label: "com.bronty13.PurpleAttic.log")
    private let handle: FileHandle?
    private let echo: Bool
    private let isoFormatter: DateFormatter
    public let logFileURL: URL?

    /// - Parameters:
    ///   - runName: short slug for this run (used in the filename).
    ///   - logDirectory: override the default `~/Library/Logs/PurpleAttic/`.
    ///   - echo: also print to stdout (true for the CLI; the GUI sets false and tails the file).
    public init(runName: String, logDirectory: URL? = nil, echo: Bool = true) {
        self.echo = echo
        self.isoFormatter = DateFormatter()
        isoFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss.SSS"
        isoFormatter.locale = Locale(identifier: "en_US_POSIX")

        let dir = logDirectory ?? AtticLogger.defaultLogDirectory()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        // Filename timestamp uses a fixed format; safe for the filesystem.
        let stamp = DateFormatter()
        stamp.dateFormat = "yyyyMMdd-HHmmss"
        stamp.locale = Locale(identifier: "en_US_POSIX")
        let url = dir.appendingPathComponent("pattic-\(runName)-\(stamp.string(from: Date())).log")

        if FileManager.default.createFile(atPath: url.path, contents: nil) {
            self.handle = try? FileHandle(forWritingTo: url)
            self.logFileURL = url
        } else {
            self.handle = nil
            self.logFileURL = nil
        }
    }

    public static func defaultLogDirectory() -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return home.appendingPathComponent("Library/Logs/PurpleAttic", isDirectory: true)
    }

    public func log(_ level: Level, _ message: String) {
        let line = "\(isoFormatter.string(from: Date())) [\(level.rawValue)] \(message)"
        queue.sync {
            if echo { print(line) }
            if let handle, let data = (line + "\n").data(using: .utf8) {
                handle.write(data)
            }
        }
    }

    public func debug(_ m: String) { log(.debug, m) }
    public func info(_ m: String)  { log(.info, m) }
    public func warn(_ m: String)  { log(.warn, m) }
    public func error(_ m: String) { log(.error, m) }

    deinit {
        try? handle?.close()
    }
}
