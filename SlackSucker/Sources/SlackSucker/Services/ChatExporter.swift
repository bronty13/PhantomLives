import Foundation

/// Reads the slackdump SQLite database produced by `slackdump archive`
/// and renders a human-readable plain-text chat log into
/// `<RunFolder>/Chat/<scope>.txt`.
///
/// Only meaningful for targeted scopes (channel / DM / thread). Skipped
/// when the user archived the entire workspace — that's too many rooms
/// to flatten into one file, and slackdump's `view` / `convert -f html`
/// is the better tool for that case.
///
/// Strategy:
/// - Shell out to `/usr/bin/sqlite3 -json` for every query. Avoids a
///   compile-time SQLite dependency, keeps parsing trivial (JSONDecoder).
/// - Load all messages + files + users into memory, then format in
///   chronological order with thread children indented under their
///   parent. Workable for archives in the thousands; not optimised for
///   the workspace-wide case, which we deliberately skip anyway.
///
/// Output format is intentionally plain ASCII so the file greps cleanly
/// and renders in any editor / terminal pager.
enum ChatExporter {

    enum Error: Swift.Error, LocalizedError {
        case sqlite(status: Int32, stderr: String)
        case noMessages

        var errorDescription: String? {
            switch self {
            case .sqlite(let s, let err):
                let trimmed = err.trimmingCharacters(in: .whitespacesAndNewlines)
                return trimmed.isEmpty
                    ? "sqlite3 exited \(s)"
                    : "sqlite3 exited \(s): \(trimmed.split(separator: "\n").first.map(String.init) ?? "")"
            case .noMessages: return "Archive contained no messages."
            }
        }
    }

    // MARK: - SQL row shapes

    struct MessageRow: Decodable {
        let ID: Int64
        let TS: String
        let CHANNEL_ID: String
        let PARENT_ID: Int64?
        let THREAD_TS: String?
        let IS_PARENT: Int
        let TXT: String?
        let USER: String?
    }

    struct UserRow: Decodable {
        let ID: String
        let USERNAME: String
        let REAL_NAME: String?
        let DISPLAY_NAME: String?

        var preferredName: String {
            if let dn = DISPLAY_NAME, !dn.isEmpty { return dn }
            if let rn = REAL_NAME, !rn.isEmpty { return rn }
            return USERNAME
        }
    }

    struct FileRow: Decodable {
        let MESSAGE_ID: Int64?
        let FILENAME: String?
        let URL: String?
    }

    struct ChannelRow: Decodable {
        let ID: String
        let NAME: String?
    }

    // MARK: - Public entry point

    /// Generate `<RunFolder>/Chat/<filename>.txt`. Caller passes the
    /// preferred filename slug (`scope.slug` from the request) and a
    /// human label for the file header. Returns the URL written.
    @discardableResult
    static func export(runFolder: URL,
                       filenameSlug: String,
                       scopeLabel: String,
                       workspace: String?) throws -> URL {
        let dbURL = runFolder.appendingPathComponent("slackdump.sqlite")
        let chatDir = runFolder.appendingPathComponent("Chat", isDirectory: true)
        try FileManager.default.createDirectory(at: chatDir, withIntermediateDirectories: true)

        let messages: [MessageRow] = try query(db: dbURL, sql: """
            SELECT ID, TS, CHANNEL_ID, PARENT_ID, THREAD_TS, IS_PARENT, TXT,
                   json_extract(CAST(DATA AS TEXT), '$.user') AS USER
            FROM MESSAGE
            ORDER BY ID ASC
        """)
        guard !messages.isEmpty else { throw Error.noMessages }

        let users: [UserRow] = (try? query(db: dbURL, sql: """
            SELECT ID, USERNAME,
                   json_extract(CAST(DATA AS TEXT), '$.real_name')              AS REAL_NAME,
                   json_extract(CAST(DATA AS TEXT), '$.profile.display_name')   AS DISPLAY_NAME
            FROM S_USER
        """)) ?? []

        let files: [FileRow] = (try? query(db: dbURL, sql: """
            SELECT MESSAGE_ID, FILENAME, URL FROM FILE
        """)) ?? []

        let channels: [ChannelRow] = (try? query(db: dbURL, sql: """
            SELECT ID, NAME FROM CHANNEL
        """)) ?? []

        let body = render(messages: messages,
                          users: users,
                          files: files,
                          channels: channels,
                          scopeLabel: scopeLabel,
                          workspace: workspace,
                          runFolderName: runFolder.lastPathComponent)
        let outURL = chatDir.appendingPathComponent("\(filenameSlug).txt")
        try body.write(to: outURL, atomically: true, encoding: .utf8)
        return outURL
    }

    // MARK: - Rendering (pure, testable)

    /// Renders a complete .txt file body. Pure — takes pre-loaded
    /// rows and returns a string; no I/O. Tests drive this directly.
    static func render(messages: [MessageRow],
                       users: [UserRow],
                       files: [FileRow],
                       channels: [ChannelRow],
                       scopeLabel: String,
                       workspace: String?,
                       runFolderName: String) -> String {
        // User-ID → display name
        var userName: [String: String] = [:]
        for u in users { userName[u.ID] = u.preferredName }

        // Message-ID → files
        var filesByMessage: [Int64: [FileRow]] = [:]
        for f in files {
            guard let mid = f.MESSAGE_ID else { continue }
            filesByMessage[mid, default: []].append(f)
        }

        // Parent-ID → child messages (already TS-ordered from the query)
        var childrenByParent: [Int64: [MessageRow]] = [:]
        for m in messages {
            guard let pid = m.PARENT_ID else { continue }
            childrenByParent[pid, default: []].append(m)
        }

        // Top-level = anything without a parent. Thread parents are
        // included here (they'll print their children inline).
        let topLevel = messages.filter { $0.PARENT_ID == nil }

        var out: [String] = []
        out.append("SlackSucker chat export")
        out.append("Scope: \(scopeLabel)")
        if let workspace { out.append("Workspace: \(workspace)") }
        out.append("Run folder: \(runFolderName)")
        out.append("Generated: \(isoNow())")
        out.append("Messages: \(messages.count)")
        out.append(String(repeating: "-", count: 60))
        out.append("")

        let resolveText = { (raw: String?) -> String in
            return Self.resolveMentions(in: raw ?? "", userName: userName)
        }

        for parent in topLevel {
            out.append(formatMessage(parent,
                                      indent: 0,
                                      userName: userName,
                                      filesByMessage: filesByMessage,
                                      resolveText: resolveText))
            // Children, if any
            if let kids = childrenByParent[parent.ID], !kids.isEmpty {
                for kid in kids {
                    out.append(formatMessage(kid,
                                              indent: 4,
                                              userName: userName,
                                              filesByMessage: filesByMessage,
                                              resolveText: resolveText))
                }
            }
            out.append("")
        }

        return out.joined(separator: "\n").appending("\n")
    }

    // MARK: - Message formatting helpers

    private static func formatMessage(_ m: MessageRow,
                                      indent: Int,
                                      userName: [String: String],
                                      filesByMessage: [Int64: [FileRow]],
                                      resolveText: (String?) -> String) -> String {
        let pad = String(repeating: " ", count: indent)
        let who = m.USER.flatMap { userName[$0] } ?? m.USER ?? "unknown"
        let when = formatTimestamp(ts: m.TS)
        let header = "\(pad)[\(when)] @\(who)"

        var body: [String] = [header]
        let text = resolveText(m.TXT)
        if !text.isEmpty {
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                body.append("\(pad)  \(line)")
            }
        }
        if let attached = filesByMessage[m.ID], !attached.isEmpty {
            for f in attached {
                let fname = f.FILENAME ?? "(unnamed)"
                body.append("\(pad)  [file] \(fname)")
            }
        }
        return body.joined(separator: "\n")
    }

    /// Replace Slack mention markup with `@displayname` when we can
    /// resolve the ID. `<@U123>` and `<@U123|fallback>` shapes covered.
    /// Channel mentions `<#C123|name>` collapse to `#name`; raw links
    /// `<https://…>` and `<https://…|label>` are left as their target
    /// or label respectively.
    nonisolated static func resolveMentions(in raw: String, userName: [String: String]) -> String {
        var s = raw
        // Mention / link markup uses `<…>` envelopes — only run the
        // regex passes when one is present. Entity decoding below
        // always runs, since `&amp;` / `&lt;` can appear in plain
        // text Slack emits without any `<>` markup.
        if s.contains("<") {
            s = replace(in: s, pattern: #"<@(U[A-Z0-9]+)(\|[^>]+)?>"#) { match in
                let id = match[1]
                if let name = userName[id] { return "@\(name)" }
                return "@\(id)"
            }
            s = replace(in: s, pattern: #"<#C[A-Z0-9]+\|([^>]+)>"#) { match in
                return "#\(match[1])"
            }
            s = replace(in: s, pattern: #"<(https?://[^|>]+)\|([^>]+)>"#) { match in
                return match[2]
            }
            s = replace(in: s, pattern: #"<(https?://[^>]+)>"#) { match in
                return match[1]
            }
        }
        // HTML-style entity escapes Slack emits in DATA blobs. Runs on
        // both marked-up and plain text — `tom &amp; jerry` needs the
        // same decode whether or not the message has other markup.
        s = s.replacingOccurrences(of: "&amp;", with: "&")
        s = s.replacingOccurrences(of: "&lt;",  with: "<")
        s = s.replacingOccurrences(of: "&gt;",  with: ">")
        return s
    }

    /// Apply a regex find-and-replace where each match's groups are
    /// passed to `transform`. Greedy, left-to-right; non-matching
    /// portions are kept verbatim.
    private static func replace(in s: String,
                                pattern: String,
                                transform: ([String]) -> String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return s }
        let ns = s as NSString
        let matches = regex.matches(in: s, range: NSRange(location: 0, length: ns.length))
        guard !matches.isEmpty else { return s }
        var result = ""
        var cursor = 0
        for m in matches {
            let range = m.range
            if range.location > cursor {
                result.append(ns.substring(with: NSRange(location: cursor, length: range.location - cursor)))
            }
            var groups: [String] = []
            for i in 0..<m.numberOfRanges {
                let r = m.range(at: i)
                groups.append(r.location == NSNotFound ? "" : ns.substring(with: r))
            }
            result.append(transform(groups))
            cursor = range.location + range.length
        }
        if cursor < ns.length {
            result.append(ns.substring(with: NSRange(location: cursor, length: ns.length - cursor)))
        }
        return result
    }

    nonisolated static func formatTimestamp(ts: String) -> String {
        // Slack TS is "<unix-seconds>.<microseconds>"
        guard let dot = ts.firstIndex(of: ".") else { return ts }
        let secs = TimeInterval(ts[..<dot]) ?? 0
        let date = Date(timeIntervalSince1970: secs)
        return Self.displayFormatter.string(from: date)
    }

    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return f
    }()

    private static func isoNow() -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f.string(from: Date())
    }

    // MARK: - SQLite shell-out

    private static func query<T: Decodable>(db: URL, sql: String) throws -> [T] {
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        proc.arguments = ["-json", db.path, sql]
        let out = Pipe()
        let err = Pipe()
        proc.standardOutput = out
        proc.standardError = err
        try proc.run()
        proc.waitUntilExit()
        if proc.terminationStatus != 0 {
            let stderr = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            throw Error.sqlite(status: proc.terminationStatus, stderr: stderr)
        }
        let raw = out.fileHandleForReading.readDataToEndOfFile()
        // sqlite3 emits "" (zero bytes) for empty result sets — JSONDecoder
        // wants at least "[]" so we substitute when empty.
        let data = raw.isEmpty ? Data("[]".utf8) : raw
        return try JSONDecoder().decode([T].self, from: data)
    }
}
