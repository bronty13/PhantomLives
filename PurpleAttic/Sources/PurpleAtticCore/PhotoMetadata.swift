import Foundation

/// A subset of an `osxphotos query --json` record — enough to decide retention and to
/// correlate the asset with its archived file. osxphotos is the metadata source (not
/// PhotoKit) specifically because it can read **keywords**, which PhotoKit cannot expose.
public struct OsxphotosRecord: Codable, Sendable {
    public let uuid: String
    public let date: String?              // ISO8601, e.g. "1997-12-31T19:00:00-05:00"
    public let favorite: Bool
    public let albums: [String]
    public let keywords: [String]
    public let originalFilename: String?  // JSON: original_filename
    public let originalFilesize: Int?     // JSON: original_filesize
    public let ismissing: Bool            // original not on disk (iCloud-only)
    public let intrash: Bool              // already in Photos trash

    /// Map to the value-typed `PhotoAsset` the retention predicate operates on. Returns nil
    /// when the date can't be parsed (such a record is treated as un-evaluable → never purged).
    public func asPhotoAsset() -> PhotoAsset? {
        guard let parsed = OsxphotosRecord.parseDate(date) else { return nil }
        return PhotoAsset(uuid: uuid, created: parsed, isFavorite: favorite,
                          albums: albums, keywords: keywords)
    }

    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime]; return f
    }()
    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter(); f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return f
    }()

    public static func parseDate(_ s: String?) -> Date? {
        guard let s, !s.isEmpty else { return nil }
        return iso.date(from: s) ?? isoFractional.date(from: s)
    }
}

/// Runs `osxphotos query` to fetch the metadata of photos created before a cutoff — the only
/// photos that could possibly be purge-eligible — keeping the JSON payload small.
public enum PhotoMetadataQuery {

    public enum QueryError: Error, CustomStringConvertible {
        case osxphotosFailed(Int32, String)
        case decodeFailed(String)
        public var description: String {
            switch self {
            case .osxphotosFailed(let c, let e): return "osxphotos query exited \(c): \(e)"
            case .decodeFailed(let m): return "Couldn't parse osxphotos JSON: \(m)"
            }
        }
    }

    /// Fetch records created strictly before `cutoff`.
    public static func recordsCreatedBefore(
        _ cutoff: Date,
        osxphotos: String,
        libraryPath: String?
    ) throws -> [OsxphotosRecord] {
        let df = DateFormatter()
        df.locale = Locale(identifier: "en_US_POSIX")
        df.dateFormat = "yyyy-MM-dd"
        var args = ["query", "--to-date", df.string(from: cutoff), "--json", "--mute"]
        if let lib = libraryPath, !lib.trimmingCharacters(in: .whitespaces).isEmpty {
            args += ["--db", lib]
        }
        let result = try ProcessRunner.capture(executable: osxphotos, arguments: args)
        guard result.exitCode == 0 else {
            throw QueryError.osxphotosFailed(result.exitCode, result.stderr)
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        do {
            return try decoder.decode([OsxphotosRecord].self,
                                      from: sanitizeNonFiniteLiterals(result.stdout))
        } catch {
            throw QueryError.decodeFailed(error.localizedDescription)
        }
    }

    /// osxphotos `--json` emits **non-standard** `Infinity` / `-Infinity` / `NaN` float literals
    /// (e.g. in a video's audio-waveform `energyValues`, or unset aesthetic scores). Python's
    /// `json` tolerates them, but Swift's JSON parser rejects them outright ("not valid JSON"),
    /// failing the whole purge preview. Replace those literals — **only in value position, never
    /// inside a string** — with `null`. A single-pass, string-aware byte scan: it tracks whether
    /// it's inside a JSON string (honoring backslash escapes) and only rewrites the bare literals
    /// outside strings, so a keyword/album/caption that literally contains "Infinity" or "NaN" is
    /// left untouched. None of the affected fields are ones `OsxphotosRecord` decodes.
    static func sanitizeNonFiniteLiterals(_ data: Data) -> Data {
        let inf = Array("Infinity".utf8)
        let nan = Array("NaN".utf8)
        let null = Array("null".utf8)
        let quote: UInt8 = 0x22, backslash: UInt8 = 0x5C, minus: UInt8 = 0x2D
        var out = [UInt8]()
        out.reserveCapacity(data.count)
        data.withUnsafeBytes { (raw: UnsafeRawBufferPointer) in
            let b = raw.bindMemory(to: UInt8.self)
            let n = b.count
            func matches(_ lit: [UInt8], _ at: Int) -> Bool {
                guard at + lit.count <= n else { return false }
                for k in 0..<lit.count where b[at + k] != lit[k] { return false }
                return true
            }
            var i = 0
            var inString = false
            while i < n {
                let c = b[i]
                if inString {
                    out.append(c)
                    if c == backslash {           // copy the escaped char verbatim
                        i += 1
                        if i < n { out.append(b[i]) }
                    } else if c == quote {
                        inString = false
                    }
                    i += 1
                    continue
                }
                if c == quote { inString = true; out.append(c); i += 1; continue }
                // Bare non-finite literals only ever start a JSON value here (a leading '-' that
                // isn't '-Infinity' is just a normal negative number → copied as-is).
                if c == minus, matches(inf, i + 1) { out.append(contentsOf: null); i += 1 + inf.count; continue }
                if c == inf[0], matches(inf, i)    { out.append(contentsOf: null); i += inf.count; continue }
                if c == nan[0], matches(nan, i)    { out.append(contentsOf: null); i += nan.count; continue }
                out.append(c)
                i += 1
            }
        }
        return Data(out)
    }
}
