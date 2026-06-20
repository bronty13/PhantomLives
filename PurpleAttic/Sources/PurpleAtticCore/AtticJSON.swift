import Foundation

/// Shared JSON coders for PurpleAttic's structured stores (run history, purge manifest,
/// purge audit). Centralized so every store dates-encodes identically (**ISO-8601**) — the
/// stores are append-only JSONL/JSON files the dashboard reads and a human can eyeball, so a
/// stable, readable date format matters. Kept separate from `ProfileStore`'s coder (which is
/// pretty-printed and dateless) so neither perturbs the other.
public enum AtticJSON {

    /// Encoder for one-object-per-line JSONL records: ISO-8601 dates, no pretty-printing
    /// (each record must be a single line).
    public static func lineEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.withoutEscapingSlashes]
        return e
    }

    /// Encoder for standalone pretty JSON documents (e.g. the single-object purge manifest).
    public static func documentEncoder() -> JSONEncoder {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return e
    }

    public static func decoder() -> JSONDecoder {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }

    /// Append one Codable value as a single JSON line to `url` (creating the file + parent dir on
    /// demand). Append-only and best-effort: a write failure is swallowed so instrumentation can
    /// never break a real run. Returns whether the line was written.
    @discardableResult
    public static func appendLine<T: Encodable>(_ value: T, to url: URL) -> Bool {
        guard let data = try? lineEncoder().encode(value) else { return false }
        var line = data
        line.append(0x0A)  // newline
        let fm = FileManager.default
        try? fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let handle = try? FileHandle(forWritingTo: url) {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: line)
            return true
        } else {
            // File doesn't exist yet — create it with this first line.
            return (try? line.write(to: url)) != nil
        }
    }

    /// Load and decode every well-formed line of a JSONL file. Malformed lines are skipped (so one
    /// truncated tail line from a crash can't lose the whole history). Returns [] if absent.
    public static func loadLines<T: Decodable>(_ type: T.Type, from url: URL) -> [T] {
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        let dec = decoder()
        var out: [T] = []
        for raw in text.split(separator: "\n", omittingEmptySubsequences: true) {
            guard let data = raw.data(using: .utf8), let v = try? dec.decode(type, from: data) else { continue }
            out.append(v)
        }
        return out
    }
}
