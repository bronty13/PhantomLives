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
}

enum JobRegistry {

    /// Which discovered agents PurpleMirror manages: the repo's own namespaces.
    /// (Scanning the LaunchAgents *directory* already excludes the runtime
    /// `application.*` GUI jobs that show up in `launchctl list`.)
    static func shouldManage(label: String) -> Bool {
        label.hasPrefix("com.phantomlives.") || label.hasPrefix("com.bronty13.")
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
                                    envKeys: ["OBSIDIAN_VAULT"])
            ),
        ]
    }

    /// PurpleAttic's per-source external archive jobs are labelled
    /// `com.bronty13.external-<kind>-sync.<source-id>`. No source name is
    /// hardcoded here — the display name + activity-log path are derived from the
    /// label's kind + id, matching what the orchestration scripts write.
    private static let externalKinds: [(prefix: String, kind: String)] = [
        ("com.bronty13.external-photo-sync.",    "Photo"),
        ("com.bronty13.external-messages-sync.", "Messages"),
    ]

    /// The profile for a discovered agent — a tailored one if we know the label,
    /// a derived one for an external-source job, else a generic plist-managed one.
    static func profile(for descriptor: AgentDescriptor) -> JobProfile {
        if let p = known[descriptor.label] { return p }
        let label = descriptor.label
        for (prefix, kind) in externalKinds where label.hasPrefix(prefix) {
            let id = String(label.dropFirst(prefix.count))     // the source id from config
            let pretty = id.isEmpty ? "" : id.prefix(1).uppercased() + id.dropFirst()
            return JobProfile(
                displayName: "External \(kind) Sync — \(pretty)",
                logKind: .purpleAtticSync,
                activityLogPathOverride: home("Library/Logs/PurpleAttic/external-\(kind.lowercased())-sync-\(id).log"),
                scheduling: .plist
            )
        }
        return JobProfile(
            displayName: displayName(forLabel: label),
            logKind: .generic,
            activityLogPathOverride: nil,   // → falls back to the plist StandardOutPath
            scheduling: .plist
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
