import Foundation

/// Typed, machine-readable metrics captured during one archival run. Until now run output was
/// only the human-readable `report-*.txt` + log; this is the structured counterpart the
/// monitoring dashboard charts over time. The engine fills it in as each phase completes;
/// every field has a safe zero/nil default so a partial (failed mid-run) record is still valid.
public struct RunMetrics: Codable, Sendable, Equatable {
    // Archive / mirror / verify
    /// Files counted in the primary archive during verify (a proxy for total archive size in items).
    public var primaryFileCount: Int = 0
    public var mirrorsCopied: Int = 0
    public var mirrorsSkipped: Int = 0
    public var mirrorsFailed: Int = 0
    public var mirrorsVerified: Int = 0
    public var verifyDiscrepancies: Int = 0

    // Off-site (restic)
    public var cloudNew: Int = 0
    public var cloudChanged: Int = 0
    public var cloudUnmodified: Int = 0
    public var cloudBytesAdded: Int64 = 0
    public var cloudSnapshot: String? = nil
    public var cloudCheckOK: Bool? = nil

    // Purge planning (no deletion — just what WOULD be purgeable this run)
    public var purgeEligible: Int = 0
    public var purgeVerified: Int = 0
    public var purgeUnverified: Int = 0
    public var purgeVerifiedBytes: Int64 = 0

    public init() {}

    /// Best-effort parse of a `ResticService.Outcome.detail` string into the typed cloud fields,
    /// e.g. "8 new, 2 changed, 364584 unmodified; +906.389 MiB (139.773 MiB stored); snapshot b1fd0247; check OK".
    /// Anything it can't parse is simply left at its default — instrumentation never throws.
    public mutating func applyCloudDetail(_ detail: String) {
        func firstInt(_ pattern: String) -> Int? {
            guard let r = detail.range(of: pattern, options: .regularExpression) else { return nil }
            return Int(detail[r].components(separatedBy: CharacterSet.decimalDigits.inverted).first { !$0.isEmpty } ?? "")
        }
        if let n = firstInt(#"\d+ new"#) { cloudNew = n }
        if let n = firstInt(#"\d+ changed"#) { cloudChanged = n }
        if let n = firstInt(#"\d+ unmodified"#) { cloudUnmodified = n }
        if let r = detail.range(of: #"snapshot [0-9a-f]+"#, options: .regularExpression) {
            cloudSnapshot = detail[r].split(separator: " ").last.map(String.init)
        }
        if detail.contains("check OK") { cloudCheckOK = true }
        else if detail.lowercased().contains("check") && detail.lowercased().contains("fail") { cloudCheckOK = false }
        // "+906.389 MiB (139.773 MiB stored)" → store the *added-to-repository* (stored) bytes,
        // which is the real off-site growth; fall back to the logical added size.
        if let stored = RunMetrics.parseByteSize(in: detail, preferringStored: true) {
            cloudBytesAdded = stored
        }
    }

    /// Parse the first `<number> <unit>` byte size in a string (KiB/MiB/GiB/TiB, decimal or binary).
    /// When `preferringStored`, returns the value inside the trailing "(… stored)" parenthetical if
    /// present (restic prints both the logical add and the deduped stored size).
    static func parseByteSize(in text: String, preferringStored: Bool) -> Int64? {
        let scope: Substring
        if preferringStored, let r = text.range(of: #"\([0-9.]+ [KMGT]i?B stored\)"#, options: .regularExpression) {
            scope = text[r]
        } else {
            scope = Substring(text)
        }
        guard let r = scope.range(of: #"[0-9.]+ [KMGT]i?B"#, options: .regularExpression) else { return nil }
        let token = scope[r]
        let parts = token.split(separator: " ")
        guard parts.count == 2, let value = Double(parts[0]) else { return nil }
        let unit = String(parts[1])
        let multipliers: [String: Double] = [
            "KiB": 1024, "MiB": 1024*1024, "GiB": 1024*1024*1024, "TiB": 1024*1024*1024*1024,
            "KB": 1000, "MB": 1_000_000, "GB": 1_000_000_000, "TB": 1_000_000_000_000,
        ]
        guard let m = multipliers[unit] else { return nil }
        return Int64(value * m)
    }
}

/// One step's outcome, persisted (the Codable mirror of `ExportEngine.StepResult`).
public struct StepRecord: Codable, Sendable, Equatable {
    public var name: String
    public var success: Bool
    public var detail: String
    public var durationSec: Double
    public init(name: String, success: Bool, detail: String, durationSec: Double) {
        self.name = name; self.success = success; self.detail = detail; self.durationSec = durationSec
    }
}

/// A persisted record of one archival run — the unit the monitoring dashboard charts. Appended
/// (JSONL) to `run-history.jsonl` after each real (non-dry) run by the CLI and the GUI alike.
public struct RunRecord: Codable, Sendable, Identifiable, Equatable {
    /// Stable id derived from the start time (yyyyMMdd-HHmmss), matching the report/log naming.
    public var id: String
    public var profileName: String
    public var startedAt: Date
    public var finishedAt: Date
    public var durationSec: Double
    public var allSucceeded: Bool
    /// Where the run came from: "scheduled" (launchd), "manual" (GUI button), "agent" (sender Mac).
    public var trigger: String
    public var steps: [StepRecord]
    public var metrics: RunMetrics
    public var newItemsArchived: Int
    public var metadataEmbedSkips: Int
    public var logFile: String?

    public init(id: String, profileName: String, startedAt: Date, finishedAt: Date,
                durationSec: Double, allSucceeded: Bool, trigger: String, steps: [StepRecord],
                metrics: RunMetrics, newItemsArchived: Int, metadataEmbedSkips: Int, logFile: String?) {
        self.id = id; self.profileName = profileName
        self.startedAt = startedAt; self.finishedAt = finishedAt
        self.durationSec = durationSec; self.allSucceeded = allSucceeded
        self.trigger = trigger; self.steps = steps; self.metrics = metrics
        self.newItemsArchived = newItemsArchived; self.metadataEmbedSkips = metadataEmbedSkips
        self.logFile = logFile
    }
}

public extension ExportEngine.RunSummary {
    /// Build the persisted `RunRecord` for this run. `trigger` records the source:
    /// "scheduled" (launchd), "manual" (GUI), or "agent" (sender Mac).
    func makeRunRecord(trigger: String) -> RunRecord {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return RunRecord(
            id: f.string(from: startedAt),
            profileName: profileName,
            startedAt: startedAt,
            finishedAt: finishedAt,
            durationSec: duration,
            allSucceeded: allSucceeded,
            trigger: trigger,
            steps: steps.map { StepRecord(name: $0.name, success: $0.success,
                                          detail: $0.detail, durationSec: $0.duration) },
            metrics: metrics,
            newItemsArchived: reviewStagedCount,
            metadataEmbedSkips: metadataEmbedSkips.count,
            logFile: logFile)
    }

    /// Append this run to the persistent history (idempotently safe to call once per run).
    @discardableResult
    func writeRunRecord(trigger: String) -> Bool {
        RunHistoryStore.append(makeRunRecord(trigger: trigger))
    }
}

/// Append-only history of `RunRecord`s in `~/Library/Application Support/PurpleAttic/run-history.jsonl`.
/// One JSON object per line — the dashboard loads them all (a few hundred at most) and charts them.
public enum RunHistoryStore {
    public static func defaultURL() -> URL {
        ProfileStore.defaultDirectory().appendingPathComponent("run-history.jsonl")
    }

    @discardableResult
    public static func append(_ record: RunRecord, to url: URL = defaultURL()) -> Bool {
        AtticJSON.appendLine(record, to: url)
    }

    /// All records, oldest-first by start time.
    public static func load(from url: URL = defaultURL()) -> [RunRecord] {
        AtticJSON.loadLines(RunRecord.self, from: url).sorted { $0.startedAt < $1.startedAt }
    }
}
