import Foundation

/// Pure aggregation of the persisted stores (`RunRecord`s + `PurgeAuditRecord`s + the latest
/// `PurgeManifest`) into the numbers and time-series the monitoring dashboard renders. Kept in
/// Core, free of SwiftUI/Charts, so the roll-ups are unit-tested without a UI.
public enum DashboardMetrics {

    /// A single (date, value) point for a chart series.
    public struct Point: Sendable, Equatable, Identifiable {
        public var date: Date
        public var value: Double
        public var id: Date { date }
        public init(date: Date, value: Double) { self.date = date; self.value = value }
    }

    /// Headline numbers for the four dashboard panels.
    public struct Summary: Sendable, Equatable {
        // Overall / archive health
        public var runsTotal: Int = 0
        public var runsOK: Int = 0
        public var lastRunAt: Date? = nil
        public var lastRunOK: Bool = false
        public var lastVerifiedFileCount: Int = 0
        public var lastDiscrepancies: Int = 0
        /// Most recent run with NO verify discrepancies (the "archive is trustworthy as of" stamp).
        public var lastCleanVerifyAt: Date? = nil

        // New items archived
        public var totalNewArchived: Int = 0

        // Purge / space reclaimed
        public var totalStaged: Int = 0
        public var totalDeleted: Int = 0
        public var bytesReclaimed: Int64 = 0
        public var lastPurgeAt: Date? = nil
        /// From the latest manifest — what's queued and verified-safe right now.
        public var readyToPurge: Int = 0
        public var readyBytes: Int64 = 0
        public var readyUnverified: Int = 0
        public var manifestComputedAt: Date? = nil

        // Off-site (B2)
        public var lastSnapshot: String? = nil
        public var lastCloudCheckOK: Bool? = nil
        public var lastCloudAt: Date? = nil
        public var totalCloudBytesAdded: Int64 = 0

        public init() {}
    }

    public static func summarize(runs: [RunRecord],
                                 audits: [PurgeAuditRecord],
                                 manifest: PurgeManifest?) -> Summary {
        var s = Summary()
        s.runsTotal = runs.count
        s.runsOK = runs.filter { $0.allSucceeded }.count
        if let last = runs.max(by: { $0.startedAt < $1.startedAt }) {
            s.lastRunAt = last.startedAt
            s.lastRunOK = last.allSucceeded
            s.lastVerifiedFileCount = last.metrics.primaryFileCount
            s.lastDiscrepancies = last.metrics.verifyDiscrepancies
        }
        s.lastCleanVerifyAt = runs
            .filter { $0.metrics.verifyDiscrepancies == 0 && $0.metrics.mirrorsVerified > 0 }
            .map { $0.startedAt }.max()

        s.totalNewArchived = runs.reduce(0) { $0 + $1.newItemsArchived }

        for a in audits {
            switch a.action {
            case .stage:  s.totalStaged += a.succeeded
            case .delete:
                s.totalDeleted += a.succeeded
                s.bytesReclaimed += a.bytes
            }
        }
        s.lastPurgeAt = audits.map { $0.timestamp }.max()

        if let m = manifest {
            s.readyToPurge = m.verifiedCount
            s.readyBytes = m.verifiedBytes
            s.readyUnverified = m.unverifiedCount
            s.manifestComputedAt = m.computedAt
        }

        // Latest run that actually pushed off-site (a snapshot id present).
        if let lastCloud = runs.filter({ $0.metrics.cloudSnapshot != nil })
            .max(by: { $0.startedAt < $1.startedAt }) {
            s.lastSnapshot = lastCloud.metrics.cloudSnapshot
            s.lastCloudCheckOK = lastCloud.metrics.cloudCheckOK
            s.lastCloudAt = lastCloud.startedAt
        }
        s.totalCloudBytesAdded = runs.reduce(0) { $0 + $1.metrics.cloudBytesAdded }
        return s
    }

    // MARK: - Time series (oldest-first; each maps one run/audit to a point)

    /// New items archived per run.
    public static func newItemsSeries(_ runs: [RunRecord]) -> [Point] {
        runs.sorted { $0.startedAt < $1.startedAt }
            .map { Point(date: $0.startedAt, value: Double($0.newItemsArchived)) }
    }

    /// Files verified in the primary archive per run (archive-growth proxy).
    public static func verifiedFilesSeries(_ runs: [RunRecord]) -> [Point] {
        runs.sorted { $0.startedAt < $1.startedAt }
            .filter { $0.metrics.primaryFileCount > 0 }
            .map { Point(date: $0.startedAt, value: Double($0.metrics.primaryFileCount)) }
    }

    /// Verify discrepancies per run (should be flat at zero — spikes are the alarm).
    public static func discrepancySeries(_ runs: [RunRecord]) -> [Point] {
        runs.sorted { $0.startedAt < $1.startedAt }
            .map { Point(date: $0.startedAt, value: Double($0.metrics.verifyDiscrepancies)) }
    }

    /// Off-site bytes added per run (deduped/stored size).
    public static func cloudBytesSeries(_ runs: [RunRecord]) -> [Point] {
        runs.sorted { $0.startedAt < $1.startedAt }
            .filter { $0.metrics.cloudBytesAdded > 0 }
            .map { Point(date: $0.startedAt, value: Double($0.metrics.cloudBytesAdded)) }
    }

    /// Cumulative photos purged (staged or deleted) over time, from the audit log.
    public static func cumulativePurgedSeries(_ audits: [PurgeAuditRecord]) -> [Point] {
        var running = 0
        return audits.sorted { $0.timestamp < $1.timestamp }.map { a in
            running += a.succeeded
            return Point(date: a.timestamp, value: Double(running))
        }
    }
}
