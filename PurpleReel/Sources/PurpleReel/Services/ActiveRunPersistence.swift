import Foundation

/// C34 (E3) — workflow-chain run resumption across app launches.
///
/// A workflow chain can take minutes to hours (verified backup of a
/// 256GB camera card, 30 transcodes, then a CSV report). Pre-C34, a
/// crash / force-quit / "Cmd-Q while a backup is running" lost
/// every per-step state and the user had to start from scratch —
/// burning the same disk + CPU again.
///
/// C34 snapshots the run's state to disk after each step completes.
/// On app launch, AppState scans the snapshots directory and offers
/// to resume any run that didn't reach a clean `finished` exit. The
/// resumed run skips steps marked `.finished` in the snapshot and
/// re-executes everything from the first incomplete step onward.
///
/// Storage: one JSON file per run under
/// `~/Library/Application Support/PurpleReel/active-runs/<UUID>.json`.
///
/// Lifecycle:
///   - `WorkflowChainRun.run()` writes the snapshot via `save(_:)`
///     before the first step + after every step transitions to
///     `.finished`.
///   - On `.finished` overall the snapshot is deleted (clean exit).
///   - On `.failed` or `.cancelled` the snapshot stays so the user
///     can choose to resume or discard via the launch prompt.
enum ActiveRunPersistence {

    /// JSON-codable snapshot of one in-flight (or interrupted)
    /// workflow chain run.
    struct Snapshot: Codable, Identifiable, Equatable {
        var id: UUID
        var chain: WorkflowChain
        var sourcePath: String
        var startedAt: Date
        var lastUpdatedAt: Date
        /// Indices into `chain.steps` that have already finished
        /// successfully. Resume reruns from the first index NOT
        /// in this set.
        var completedStepIndices: [Int]
    }

    /// Anchored at Application Support to survive across app
    /// reinstalls and to share the same retention story as the
    /// rest of PurpleReel's user-data files.
    static var directoryURL: URL {
        let support = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return support
            .appendingPathComponent("PurpleReel", isDirectory: true)
            .appendingPathComponent("active-runs", isDirectory: true)
    }

    /// Test seam — let unit tests override the directory without
    /// having to mock FileManager. Set once at setUp, restored at
    /// tearDown. Nil means "use the default directoryURL".
    static var directoryOverride: URL?

    private static var effectiveDirectory: URL {
        directoryOverride ?? directoryURL
    }

    /// Write the snapshot. Idempotent — same id overwrites. Errors
    /// are logged via NSLog rather than thrown; the chain run
    /// shouldn't fail because we couldn't persist its bookmark.
    static func save(_ snapshot: Snapshot) {
        let dir = effectiveDirectory
        do {
            try FileManager.default.createDirectory(
                at: dir, withIntermediateDirectories: true
            )
            let url = dir.appendingPathComponent("\(snapshot.id).json")
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(snapshot)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("[PurpleReel] active-run snapshot save failed: \(error)")
        }
    }

    /// Delete the snapshot for `id`. Called on clean `.finished`
    /// exit so the launch prompt doesn't keep nagging about
    /// successfully-completed runs.
    static func delete(_ id: UUID) {
        let url = effectiveDirectory.appendingPathComponent("\(id).json")
        try? FileManager.default.removeItem(at: url)
    }

    /// Enumerate every snapshot currently on disk, newest first.
    /// Used by the launch-time resume prompt to surface
    /// interrupted runs. Skips files that fail to decode (likely
    /// from a future PurpleReel version with a different schema).
    static func loadAll() -> [Snapshot] {
        let fm = FileManager.default
        let dir = effectiveDirectory
        guard let contents = try? fm.contentsOfDirectory(
            at: dir,
            includingPropertiesForKeys: nil
        ) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        var out: [Snapshot] = []
        for url in contents where url.pathExtension == "json" {
            guard let data = try? Data(contentsOf: url),
                  let snap = try? decoder.decode(Snapshot.self, from: data)
            else { continue }
            out.append(snap)
        }
        return out.sorted { $0.lastUpdatedAt > $1.lastUpdatedAt }
    }

    /// Wipe every snapshot. The "Discard all" button in the resume
    /// prompt calls this when the user wants to forget every
    /// interrupted run.
    static func clearAll() {
        let fm = FileManager.default
        let dir = effectiveDirectory
        guard let contents = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: nil
        ) else { return }
        for url in contents where url.pathExtension == "json" {
            try? fm.removeItem(at: url)
        }
    }
}
