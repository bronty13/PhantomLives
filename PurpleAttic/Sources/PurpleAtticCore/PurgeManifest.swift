import Foundation

/// The persisted output of a nightly purge *plan* — written by the (headless, non-deleting)
/// archive run after it verifies the archive, and consumed by the GUI stage-agent that moves the
/// verified set into the "To Delete" album. It is **analysis, never an instruction to delete**:
/// it lists the photos that are aged-out, un-pinned, AND present in ≥2 archive copies, so a human
/// (or the staging step) can act on a trustworthy, pre-computed set instead of re-querying live.
public struct PurgeManifest: Codable, Sendable, Equatable {
    /// One verified-deletable photo. UUID is what the PhotoKit stager resolves to a `PHAsset`.
    public struct Item: Codable, Sendable, Equatable, Identifiable {
        public var uuid: String
        public var filename: String
        public var date: Date
        public var sizeBytes: Int64
        public var id: String { uuid }
        public init(uuid: String, filename: String, date: Date, sizeBytes: Int64) {
            self.uuid = uuid; self.filename = filename; self.date = date; self.sizeBytes = sizeBytes
        }
    }

    public var computedAt: Date
    public var profileName: String
    public var cutoff: Date
    public var keepWindowDays: Int
    public var recordsConsidered: Int
    public var eligibleCount: Int
    public var verifiedCount: Int
    public var unverifiedCount: Int
    public var verifiedBytes: Int64
    /// The verified-deletable items only (the set the stage-agent acts on).
    public var items: [Item]

    public init(computedAt: Date, profileName: String, cutoff: Date, keepWindowDays: Int,
                recordsConsidered: Int, eligibleCount: Int, verifiedCount: Int, unverifiedCount: Int,
                verifiedBytes: Int64, items: [Item]) {
        self.computedAt = computedAt; self.profileName = profileName
        self.cutoff = cutoff; self.keepWindowDays = keepWindowDays
        self.recordsConsidered = recordsConsidered; self.eligibleCount = eligibleCount
        self.verifiedCount = verifiedCount; self.unverifiedCount = unverifiedCount
        self.verifiedBytes = verifiedBytes; self.items = items
    }

    /// Build a manifest from a freshly-computed `PurgePlan`. Only the **verified** candidates become
    /// `items` (the only set anything may ever stage/delete); the unverified count is recorded for
    /// the dashboard so the user can see how many photos are blocked on an incomplete archive.
    public init(from plan: PurgePlan, profileName: String, keepWindowDays: Int, computedAt: Date) {
        self.computedAt = computedAt
        self.profileName = profileName
        self.cutoff = plan.cutoff
        self.keepWindowDays = keepWindowDays
        self.recordsConsidered = plan.recordsConsidered
        self.eligibleCount = plan.candidates.count
        self.verifiedCount = plan.verified.count
        self.unverifiedCount = plan.unverified.count
        self.verifiedBytes = Int64(plan.verifiedBytes)
        self.items = plan.verified.map {
            Item(uuid: $0.uuid, filename: $0.filename, date: $0.date, sizeBytes: Int64($0.sizeBytes))
        }
    }

    /// True when the manifest is older than `maxAge` relative to `now` — the stage-agent refuses a
    /// stale manifest so it never acts on a plan that no longer reflects the library/archive.
    public func isStale(asOf now: Date, maxAge: TimeInterval) -> Bool {
        now.timeIntervalSince(computedAt) > maxAge
    }
}

/// Reads/writes the single latest `purge-plan.json` in the support directory. One document (not
/// JSONL) — only the most recent plan matters; each run overwrites it. The per-run *counts* live
/// durably in `RunRecord.metrics`, so overwriting the manifest loses no history.
public enum PurgeManifestStore {
    public static func defaultURL() -> URL {
        ProfileStore.defaultDirectory().appendingPathComponent("purge-plan.json")
    }

    @discardableResult
    public static func write(_ manifest: PurgeManifest, to url: URL = defaultURL()) -> Bool {
        guard let data = try? AtticJSON.documentEncoder().encode(manifest) else { return false }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    public static func read(from url: URL = defaultURL()) -> PurgeManifest? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? AtticJSON.decoder().decode(PurgeManifest.self, from: data)
    }
}
