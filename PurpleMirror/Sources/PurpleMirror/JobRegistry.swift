import Foundation

/// How a job's schedule is managed.
enum Scheduling: Equatable {
    /// Managed by a script that supports `--install-agent <secs>` / `--uninstall-agent`
    /// (the Obsidian sync). `envKeys` are environment keys to carry over from the
    /// installed plist when re-installing (e.g. `OBSIDIAN_VAULT`, baked into the plist).
    case script(path: String, envKeys: [String])
    /// Managed by editing the plist's `StartInterval` and `launchctl bootstrap/bootout`
    /// directly (PurpleAttic's hand-written external-source plists, and any unknown agent).
    case plist
}

/// Per-label presentation + behavior. Discovery is generic; a profile *enhances*
/// a known job with a friendly name, the right log path, tailored log parsing,
/// and its scheduling mechanism. Unknown jobs get a generic profile.
struct JobProfile: Equatable {
    var displayName: String
    var logKind: SyncStatusParser.LogKind
    /// Use this log path instead of the plist's `StandardOutPath` (e.g. the human
    /// activity log differs from the launchd stdout capture).
    var activityLogPathOverride: String?
    var scheduling: Scheduling
    /// Section the job is grouped under in the UI (e.g. the source "Rachel"); jobs
    /// are grouped by this but still operated on individually.
    var group: String = "Other"
    /// Compact name shown within a group (e.g. "Photo"); defaults to displayName.
    var shortName: String = ""
}

enum JobRegistry {

    /// Which discovered agents PurpleMirror manages: the repo's own namespaces.
    /// (Scanning the LaunchAgents *directory* already excludes the runtime
    /// `application.*` GUI jobs that show up in `launchctl list`.)
    static func shouldManage(label: String) -> Bool {
        // The repo's own namespaces, plus any explicitly-profiled job outside them
        // (e.g. brew-autoupdate's `com.user.brew-autoupdate`).
        known[label] != nil
            || label.hasPrefix("com.phantomlives.")
            || label.hasPrefix("com.bronty13.")
    }

    private static func home(_ rel: String) -> String {
        (NSHomeDirectory() as NSString).appendingPathComponent(rel)
    }

    /// Tailored profiles for jobs we understand by exact label.
    private static var known: [String: JobProfile] {
        [
            "com.phantomlives.obsidian-sync": JobProfile(
                displayName: "Obsidian Sync",
                logKind: .obsidian,
                activityLogPathOverride: home("Library/Logs/phantomlives-obsidian-sync.log"),
                scheduling: .script(path: home("dev/PhantomLives/sync-md-to-obsidian.sh"),
                                    envKeys: ["OBSIDIAN_VAULT"]),
                group: "Obsidian", shortName: "Markdown Sync"
            ),
            // PurpleAttic's scheduled LOCAL photo archive (osxphotos → ROG_WHITE → LACIE → verify →
            // restic/B2). Distinct from the external-source *pull* jobs below: this is the on-Mac
            // run, parsed from pattic's echoed run log via `.purpleAttic`.
            "com.bronty13.PurpleAttic.archive": JobProfile(
                displayName: "Photo Archive",
                logKind: .purpleAttic,
                activityLogPathOverride: home("Library/Logs/PurpleAttic/scheduler.out.log"),
                scheduling: .plist,
                group: "Photos", shortName: "Photo Archive"
            ),
            // Hourly ATW listing-repost bot (Node/Playwright). Single-pass per launchd invocation;
            // its log surfaces "Reposted N listing(s)" + a 24h repost tally.
            "com.bronty13.atw-repost-bot": JobProfile(
                displayName: "ATW Repost Bot",
                logKind: .atwRepost,
                activityLogPathOverride: home("Library/Logs/atw-repost-bot/atw-repost-bot.log"),
                scheduling: .plist,
                group: "Bots", shortName: "ATW Repost"
            ),
            // brew-autoupdate (Bash + launchd). Outside the repo namespaces, so explicitly profiled.
            // Calendar-scheduled (StartCalendarInterval), so its "Run every" interval isn't meaningful —
            // enable/disable, Run Now, and View Log all work. Stdout log has bracketed timestamps.
            "com.user.brew-autoupdate": JobProfile(
                displayName: "Homebrew Auto-Update",
                logKind: .brewAutoupdate,
                activityLogPathOverride: home("Library/Logs/brew-autoupdate/launchd-stdout.log"),
                scheduling: .plist,
                group: "Maintenance", shortName: "Homebrew"
            ),
        ]
    }

    /// PurpleAttic's per-source external archive jobs are labelled
    /// `com.bronty13.external-<kind>-sync.<source-id>`. No source name is
    /// hardcoded here — the display name + activity-log path are derived from the
    /// label's kind + id, matching what the orchestration scripts write.
    /// Each entry: the label token (as it appears in `external-<token>-sync.<id>`
    /// and the log filename) → the human display kind.
    private static let externalKinds: [(token: String, kind: String)] = [
        ("photo",      "Photo"),
        ("messages",   "Messages"),
        ("notes",      "Notes"),
        ("reminders",  "Reminders"),
        ("safari",     "Safari"),
        ("voicememos", "Voice Memos"),
        ("calls",      "Calls"),
        ("calendar",   "Calendar"),
        ("books",      "Books"),
        ("podcasts",   "Podcasts"),
        ("stickies",   "Stickies"),
        ("mail",       "Mail"),
        ("index",      "Landing Page"),
    ]

    /// The profile for a discovered agent — a tailored one if we know the label,
    /// a derived one for an external-source job, else a generic plist-managed one.
    static func profile(for descriptor: AgentDescriptor) -> JobProfile {
        if let p = known[descriptor.label] { return p }
        let label = descriptor.label
        for (token, kind) in externalKinds {
            let prefix = "com.bronty13.external-\(token)-sync."
            guard label.hasPrefix(prefix) else { continue }
            let id = String(label.dropFirst(prefix.count))     // the source id from config
            let pretty = id.isEmpty ? "" : id.prefix(1).uppercased() + id.dropFirst()
            return JobProfile(
                displayName: "External \(kind) Sync — \(pretty)",
                logKind: .purpleAtticSync,
                activityLogPathOverride: home("Library/Logs/PurpleAttic/external-\(token)-sync-\(id).log"),
                scheduling: .plist,
                group: pretty.isEmpty ? "Other" : pretty,   // group by source
                shortName: kind                              // compact name within the group
            )
        }
        return JobProfile(
            displayName: displayName(forLabel: label),
            logKind: .generic,
            activityLogPathOverride: nil,   // → falls back to the plist StandardOutPath
            scheduling: .plist,
            group: "Other", shortName: displayName(forLabel: label)
        )
    }

    /// Prettify an unknown reverse-DNS label → a title.
    /// `com.bronty13.disk-cleaner` → "Disk Cleaner".
    static func displayName(forLabel label: String) -> String {
        let leaf = label.split(separator: ".").last.map(String.init) ?? label
        let words = leaf.split(whereSeparator: { $0 == "-" || $0 == "_" })
        return words.map { $0.prefix(1).uppercased() + $0.dropFirst() }.joined(separator: " ")
    }
}
