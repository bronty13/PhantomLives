import Foundation

/// Pure renderers for an ad-hoc B2 file report — CSV / JSON / plain text — over the cached listing.
/// Kept free of the filesystem so they're unit-testable; the app writes the rendered string to
/// `~/Downloads/PurpleAttic/` (the PhantomLives output convention).
public enum AdhocReport {

    public enum Format: String, CaseIterable, Sendable {
        case csv, json, txt
        public var ext: String { rawValue }
        public var label: String {
            switch self {
            case .csv: return "CSV"
            case .json: return "JSON"
            case .txt: return "Text"
            }
        }
    }

    /// A flattened, report-facing row (excludes the cache's internal `lastSeen`).
    struct Row: Codable, Equatable {
        let path: String
        let name: String
        let size: Int64
        let modified: String      // ISO-8601
        let isDir: Bool
        let sha1: String?
        let tier: String?
    }

    static func rows(_ files: [AdhocFile]) -> [Row] {
        let iso = ISO8601DateFormatter()
        return files
            .sorted { $0.path < $1.path }
            .map { Row(path: $0.path, name: $0.name, size: $0.size,
                       modified: iso.string(from: $0.modTime), isDir: $0.isDir,
                       sha1: $0.sha1, tier: $0.tier) }
    }

    public static func render(_ files: [AdhocFile], format: Format, generatedAt: Date) -> String {
        switch format {
        case .csv: return csv(files)
        case .json: return json(files)
        case .txt: return txt(files, generatedAt: generatedAt)
        }
    }

    // MARK: - CSV

    static func csvEscape(_ s: String) -> String {
        guard s.contains(",") || s.contains("\"") || s.contains("\n") else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    static func csv(_ files: [AdhocFile]) -> String {
        var out = "path,name,size,modified,isDir,sha1,tier\n"
        for r in rows(files) {
            out += [r.path, r.name, String(r.size), r.modified,
                    r.isDir ? "true" : "false", r.sha1 ?? "", r.tier ?? ""]
                .map(csvEscape).joined(separator: ",") + "\n"
        }
        return out
    }

    // MARK: - JSON

    static func json(_ files: [AdhocFile]) -> String {
        let enc = JSONEncoder()
        enc.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? enc.encode(rows(files)),
              let s = String(data: data, encoding: .utf8) else { return "[]" }
        return s
    }

    // MARK: - Plain text

    static func txt(_ files: [AdhocFile], generatedAt: Date) -> String {
        let total = files.reduce(Int64(0)) { $0 + max(0, $1.size) }
        let df = DateFormatter(); df.dateStyle = .medium; df.timeStyle = .short
        var out = "PurpleAttic — Ad-hoc B2 file report\n"
        out += "Generated: \(df.string(from: generatedAt))\n"
        out += "Items: \(files.count)   Total: \(ByteCountFormatter.string(fromByteCount: total, countStyle: .file))\n"
        out += String(repeating: "=", count: 52) + "\n"
        for f in files.sorted(by: { $0.path < $1.path }) {
            let size = f.isDir ? "—" : ByteCountFormatter.string(fromByteCount: max(0, f.size), countStyle: .file)
            out += "\(f.path)\t\(size)\n"
        }
        return out
    }
}
