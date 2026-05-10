import Foundation
import PurpleDedupCore

/// FR-5.9 dry-run report: every cluster + per-file decision in a stable
/// JSON shape that's diffable (week-over-week deduping reviews) and
/// audit-friendly. Building the value-typed `Plan` is pure data work; the
/// NSSavePanel + write step lives in ContentView so the data-only paths
/// (CLI export, future tests) can build the same payload without dragging
/// AppKit in.
///
/// Promoting these types to top-level (they used to be nested inside
/// `savePlanJSON`) lets `Plan.build(...)` stay a focused pure function and
/// makes the report shape obvious to anyone reading the code.
struct PlanFile: Codable {
    let path: String
    /// `"keep"` / `"delete"` / `"(no decision)"`.
    let decision: String
    let reason: String?
    let isManualOverride: Bool
    let sizeBytes: Int64
}

struct PlanCluster: Codable {
    let id: String
    let kind: String
    let fileCount: Int
    let reclaimableBytes: Int64
    let files: [PlanFile]
}

struct Plan: Codable {
    let appName: String
    let appVersion: String
    let generatedAtISO: String
    let totalFiles: Int
    let totalMarkedDelete: Int
    let totalReclaimableBytes: Int64
    let stageFolder: String?
    let clusters: [PlanCluster]

    /// Construct a plan from the GUI's runtime state. Pure: takes only the
    /// data it needs and returns a fully-formed `Plan` ready to encode.
    /// Caller decides where to write it (NSSavePanel, CLI stdout, etc.).
    ///
    /// - Parameters:
    ///   - clusterFileMap: ordered list of (encoded ClusterID, files-in-cluster).
    ///     Use `currentClusterFileMap()` from the GUI side.
    ///   - decisionsByCluster: engine recommendations per cluster.
    ///   - manualOverrides: user overrides per cluster (win over recommendations).
    ///   - filesToDelete: cross-cluster set the toolbar's Trash button targets;
    ///     used to compute per-cluster reclaim bytes.
    ///   - totalReclaimableBytes: the GUI's already-aggregated reclaim total
    ///     (sum of cluster `totalReclaimableBytes`).
    ///   - stageFolder: optional path to override Trash with a stage folder.
    static func build(
        clusterFileMap: [(String, [DiscoveredFile])],
        decisionsByCluster: [String: ClusterDecisions],
        manualOverrides: [String: [URL: Decision]],
        filesToDelete: [DiscoveredFile],
        totalReclaimableBytes: Int64,
        stageFolder: String?
    ) -> Plan {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]

        var planClusters: [PlanCluster] = []
        var totalMarked = 0

        for (id, files) in clusterFileMap {
            let decisions = decisionsByCluster[id]?.perFile ?? [:]
            let manual = manualOverrides[id] ?? [:]
            let kind: String
            switch ClusterID(id)?.kind {
            case .exact:   kind = "exact"
            case .photo:   kind = "similar_photo"
            case .video:   kind = "similar_video"
            case .burst:   kind = "similar_burst"
            case .rotated: kind = "similar_rotated"
            case nil:      kind = "unknown"
            }

            let planFiles: [PlanFile] = files.map { f in
                let effective = manual[f.url] ?? decisions[f.url]
                let isManual = manual[f.url] != nil
                let (decisionStr, reason): (String, String?)
                switch effective {
                case .keep(let r):   decisionStr = "keep";   reason = r
                case .delete(let r): decisionStr = "delete"; reason = r; totalMarked += 1
                case nil:            decisionStr = "(no decision)"; reason = nil
                }
                return PlanFile(
                    path: f.url.path, decision: decisionStr, reason: reason,
                    isManualOverride: isManual, sizeBytes: f.sizeBytes
                )
            }

            let reclaim = filesToDelete
                .filter { f in files.contains(where: { $0.url == f.url }) }
                .reduce(Int64(0)) { $0 + $1.sizeBytes }

            planClusters.append(PlanCluster(
                id: id, kind: kind, fileCount: files.count,
                reclaimableBytes: reclaim, files: planFiles
            ))
        }

        return Plan(
            appName: PurpleDedup.appName,
            appVersion: PurpleDedup.coreVersion,
            generatedAtISO: iso.string(from: Date()),
            totalFiles: clusterFileMap.reduce(0) { $0 + $1.1.count },
            totalMarkedDelete: totalMarked,
            totalReclaimableBytes: totalReclaimableBytes,
            stageFolder: stageFolder,
            clusters: planClusters
        )
    }
}
