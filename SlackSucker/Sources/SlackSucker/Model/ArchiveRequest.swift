import Foundation

/// The user-selectable target of an archive run. `entireWorkspace` lets
/// slackdump archive everything its credentials can see. The other cases
/// constrain the run to a single conversation:
///
/// - `.channel`: a public / private channel, by ID (`C…`) or full URL.
/// - `.dm`: a direct message conversation, by ID (`D…`/`G…`) or URL.
/// - `.threadURL`: a single thread within a channel; slackdump accepts
///   the standard Slack message permalink as-is.
///
/// `humanLabel` and `slug` are presentation helpers used by the runner
/// to name the timestamped output subfolder.
enum ArchiveScope: Codable, Equatable {
    case entireWorkspace
    case channel(idOrURL: String, displayName: String?)
    case dm(idOrURL: String, displayName: String?)
    case threadURL(String)

    /// What the user sees in the form / sidebar / history.
    var humanLabel: String {
        switch self {
        case .entireWorkspace:                       return "Entire workspace"
        case .channel(let id, let name):             return name ?? id
        case .dm(let id, let name):                  return name ?? id
        case .threadURL(let url):                    return "Thread"
            + (url.split(separator: "/").last.map { " (…\($0))" } ?? "")
        }
    }

    /// Filename-safe identifier for the output subfolder. Trimmed to a
    /// reasonable length; ASCII only.
    var slug: String {
        let raw: String
        switch self {
        case .entireWorkspace:                       raw = "workspace"
        case .channel(let id, let name):             raw = name ?? id
        case .dm(let id, let name):                  raw = name ?? id
        case .threadURL(let url):                    raw = "thread_" + (url.split(separator: "/").last.map(String.init) ?? "x")
        }
        let allowed = Set("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-_")
        let cleaned = String(raw.unicodeScalars.map { allowed.contains(Character($0)) ? Character($0) : "_" })
        return String(cleaned.prefix(40))
    }

    /// The single argument slackdump archive uses to scope to a specific
    /// conversation. `nil` means "no scope arg" → entire workspace.
    var slackdumpScopeArgument: String? {
        switch self {
        case .entireWorkspace:                       return nil
        case .channel(let id, _):                    return id
        case .dm(let id, _):                         return id
        case .threadURL(let url):                    return url
        }
    }

    /// Extract `(channelID, threadTS, threadTSSeconds)` from a Slack
    /// permalink of the form
    ///
    ///     https://<workspace>.slack.com/archives/C<channel>/p<digits>
    ///
    /// where `<digits>` is the slack TS with the decimal point removed
    /// (10 seconds + 6 microseconds, fixed width). Returns nil if the
    /// URL doesn't match.
    ///
    /// Used by `ArchiveRequest.argumentList()` to substitute the
    /// channel + time-bracket workaround for slackdump's broken
    /// thread-URL archive behavior — thread URLs alone don't trigger
    /// file downloads in slackdump 4.x even when `-files=true`. The
    /// equivalent channel-archive with a 2-second time bracket around
    /// the parent TS does.
    nonisolated static func parseThreadURL(_ url: String) -> (channelID: String,
                                                              threadTSString: String,
                                                              threadTSSeconds: TimeInterval)? {
        let pattern = #"/archives/(C[A-Z0-9]+)/p(\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let ns = url as NSString
        let range = NSRange(location: 0, length: ns.length)
        guard let m = regex.firstMatch(in: url, options: [], range: range),
              m.numberOfRanges == 3 else { return nil }
        let channelID = ns.substring(with: m.range(at: 1))
        let digits = ns.substring(with: m.range(at: 2))
        // Slack permalink TS is fixed 10 seconds + 6 microseconds.
        // Anything shorter than 7 digits can't carry seconds-level
        // precision, so bail.
        guard digits.count >= 7 else { return nil }
        let dotIdx = digits.index(digits.endIndex, offsetBy: -6)
        let secsPart = String(digits[..<dotIdx])
        let microsPart = String(digits[dotIdx...])
        let tsString = "\(secsPart).\(microsPart)"
        guard let seconds = TimeInterval(secsPart) else { return nil }
        return (channelID, tsString, seconds)
    }
}

/// Time-window selector. `.all` omits both `-time-from` and `-time-to`.
/// `.range` always emits both — leaving one open invites a 1970 → now
/// scan that hammers Slack's API for no good reason.
enum ArchiveTimeRange: Codable, Equatable {
    case all
    case range(from: Date, to: Date)
}

/// Everything needed to invoke `slackdump archive`. Built by the form,
/// snapshotted by `ArchiveRunner` so the in-flight request is recoverable
/// for the run-history append on completion.
struct ArchiveRequest: Codable, Equatable {
    /// nil → slackdump uses its "current" workspace.
    var workspace: String?
    var scope: ArchiveScope
    var timeRange: ArchiveTimeRange
    var includeFiles: Bool
    var includeAvatars: Bool
    /// Only meaningful for `.entireWorkspace`; ignored otherwise. The
    /// argv builder still emits the flag whenever the toggle is on so
    /// the user can see exactly what was requested in the log.
    var memberOnly: Bool
    /// After slackdump exits, sort attachments from `__uploads/` into
    /// `Videos/`, `Photos/`, `Audio/`, `Other/` subfolders at the
    /// run-folder root. False = leave slackdump's native layout
    /// untouched. Read by `ArchiveRunner`, not by the argv builder
    /// (slackdump itself doesn't know about this option).
    var organizeFiles: Bool = true
    /// How `FileOrganizer` orders the `0001_, 0002_, …` prefix within
    /// each category. `.none` skips the prefix. Only honored when
    /// `organizeFiles` is also on.
    var fileOrdering: FileOrdering = .messageTimestamp
    /// Post-processing toggles — none of these touch slackdump itself.
    var generateHashes: Bool = false
    var hashAlgorithms: Set<HashAlgorithm> = [.sha256]
    var transcribeMedia: Bool = false
    var transcribeModel: TranscriptionModel = .turbo
    var stripPhotoMetadata: Bool = false
    var bakeOrientation: Bool = false
    /// Resolved path slackdump should write into. The runner computes
    /// this as `<settings.outputDir>/<scope.slug>_<YYYYMMDD_HHmmss>`.
    var outputDir: URL
    var debug: Bool = false

    /// slackdump command-line invocation for `archive`. The bundled
    /// binary is positional; this builder produces only the arguments.
    ///
    /// Special-case for `.threadURL` scope: slackdump 4.x doesn't fetch
    /// attachments when the scope argument is a Slack permalink — even
    /// with `-files=true`. The MESSAGE row lands with the right
    /// NUM_FILES, but the FILE table is empty and __uploads/ is never
    /// created. To work around this, we substitute the channel ID +
    /// `-time-from`/`-time-to` bracket of ±1 second around the
    /// permalink's TS. That captures only the target message and
    /// triggers slackdump's normal channel-archive file-download path.
    /// Any user-supplied time range is ignored for thread scope, since
    /// a thread is identified by a single TS.
    func argumentList() -> [String] {
        var args: [String] = ["archive"]
        if let workspace, !workspace.isEmpty {
            args += ["-workspace", workspace]
        }
        args += ["-o", outputDir.path]
        if !includeFiles  { args += ["-files=false"] }
        if includeAvatars { args += ["-avatars"] }
        if memberOnly     { args += ["-member-only"] }

        if case .threadURL(let url) = scope,
           let parsed = ArchiveScope.parseThreadURL(url) {
            let from = Date(timeIntervalSince1970: parsed.threadTSSeconds - 1)
            let to   = Date(timeIntervalSince1970: parsed.threadTSSeconds + 1)
            args += ["-time-from", Self.formatter.string(from: from)]
            args += ["-time-to",   Self.formatter.string(from: to)]
            if debug { args += ["-v"] }
            args.append(parsed.channelID)
            return args
        }

        switch timeRange {
        case .all:
            break
        case .range(let from, let to):
            args += ["-time-from", Self.formatter.string(from: from)]
            args += ["-time-to",   Self.formatter.string(from: to)]
        }
        if debug { args += ["-v"] }
        if let s = scope.slackdumpScopeArgument {
            args.append(s)
        }
        return args
    }

    /// slackdump's documented time format: `YYYY-MM-DDTHH:MM:SS`, UTC.
    static let formatter: DateFormatter = {
        let f = DateFormatter()
        f.locale   = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone(identifier: "UTC")
        f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss"
        return f
    }()

    /// Compose the per-run subfolder URL from a settings-level output
    /// root + this request's scope. Pure; used by the form before the
    /// runner takes over.
    static func computeRunFolder(root: URL, scope: ArchiveScope, now: Date = Date()) -> URL {
        let stamp = Self.folderStamp.string(from: now)
        return root.appendingPathComponent("\(scope.slug)_\(stamp)", isDirectory: true)
    }

    private static let folderStamp: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyyMMdd_HHmmss"
        return f
    }()
}
