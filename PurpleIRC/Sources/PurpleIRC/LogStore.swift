import Foundation

/// Append-only persistent log writer. Files are laid out as
/// `<logsDir>/<networkSlug>/<bufferSlug>.log`. Each line is a timestamped
/// plain-text representation of a `ChatLine`, with mIRC codes stripped so the
/// file stays grep-friendly. Rotation is simple: when a file exceeds
/// `rotateBytes` we rename it to `.log.1` (overwriting any previous rotation).
///
/// The store is explicitly off the main actor so file IO doesn't stall the
/// UI. IRCConnection hands lines to it via a detached Task.
actor LogStore {
    private let baseURL: URL
    private let fm = FileManager.default
    private let rotateBytes: Int
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    init(baseURL: URL, rotateBytes: Int = 4 * 1024 * 1024) {
        self.baseURL = baseURL
        self.rotateBytes = rotateBytes
        try? fm.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }

    func append(network: String, buffer: String, line: String) {
        let url = fileURL(network: network, buffer: buffer)
        do {
            try ensureParent(url: url)
            rotateIfNeeded(url: url)
            let record = "\(Self.iso.string(from: Date())) \(line)\n"
            guard let data = record.data(using: .utf8) else { return }
            if fm.fileExists(atPath: url.path) {
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                try handle.close()
            } else {
                try data.write(to: url, options: .atomic)
            }
        } catch {
            NSLog("PurpleIRC: log write failed for \(network)/\(buffer): \(error)")
        }
    }

    /// Synchronous read used by the log viewer. Returns the file contents or
    /// nil if the file doesn't exist. Kept as a simple blocking read — log
    /// files are capped at ~rotateBytes so this is bounded.
    func read(network: String, buffer: String) -> String? {
        let url = fileURL(network: network, buffer: buffer)
        guard let data = try? Data(contentsOf: url),
              let text = String(data: data, encoding: .utf8) else { return nil }
        return text
    }

    func fileURL(network: String, buffer: String) -> URL {
        baseURL
            .appendingPathComponent(slug(network), isDirectory: true)
            .appendingPathComponent(slug(buffer) + ".log", isDirectory: false)
    }

    private func ensureParent(url: URL) throws {
        let parent = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: parent.path) {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        }
    }

    private func rotateIfNeeded(url: URL) {
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber,
              size.intValue >= rotateBytes else { return }
        let rotated = url.appendingPathExtension("1")
        try? fm.removeItem(at: rotated)
        try? fm.moveItem(at: url, to: rotated)
    }

    /// Filesystem-safe slug: lowercased, path separators and `#` replaced with
    /// `_`, whitespace collapsed. Keep it simple — servers / channels rarely
    /// need anything clever.
    private func slug(_ s: String) -> String {
        var out = s.lowercased()
        let bad: Set<Character> = ["/", "\\", ":", "*", "?", "\"", "<", ">", "|", "\0"]
        out = String(out.map { bad.contains($0) ? "_" : $0 })
        if out.hasPrefix("#") { out = "chan_" + out.dropFirst() }
        if out.isEmpty { out = "_" }
        return out
    }
}

extension ChatLine {
    /// Plain-text one-liner for persistent logs. No IRC codes, no SwiftUI
    /// styling — just a human-readable summary of the event. Used by the
    /// LogStore; not the right surface for bots (they want structured
    /// events via IRCConnectionEvent).
    func toLogLine() -> String {
        switch kind {
        case .info:           return "* \(text)"
        case .error:          return "! \(text)"
        case .motd:           return "MOTD \(text)"
        case .privmsg(let n, let isSelf):
            return "\(isSelf ? "→" : "<")\(n)\(isSelf ? "→" : ">") \(IRCFormatter.stripCodes(text))"
        case .action(let n):  return "* \(n) \(IRCFormatter.stripCodes(text))"
        case .notice(let f):  return "-\(f)- \(IRCFormatter.stripCodes(text))"
        case .join(let n):    return "→ \(n) joined"
        case .part(let n, let r):
            return "← \(n) left" + (r.map { " (\(IRCFormatter.stripCodes($0)))" } ?? "")
        case .quit(let n, let r):
            return "← \(n) quit" + (r.map { " (\(IRCFormatter.stripCodes($0)))" } ?? "")
        case .nick(let o, let nw):
            return "\(o) → \(nw)"
        case .topic(let setter):
            return (setter.map { "\($0) set topic: " } ?? "topic: ") + IRCFormatter.stripCodes(text)
        case .raw:            return text
        }
    }

    /// Not all lines are worth persisting. Server/MOTD numeric spam is noisy
    /// and usually skipped — toggleable via settings.
    var isNoisyLogKind: Bool {
        switch kind {
        case .motd, .info, .error: return true
        default: return false
        }
    }
}
