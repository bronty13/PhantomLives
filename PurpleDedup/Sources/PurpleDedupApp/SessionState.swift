import Foundation
import PurpleDedupCore

/// Snapshot of the user's review state at a moment in time. Persisted to
/// `~/Library/Application Support/PurpleDedup/session-state.json` whenever
/// decisions or manual overrides change, restored on app launch. Cluster-
/// level data (the cluster lists themselves) is NOT persisted — those derive
/// from the next scan, which the cache makes near-instant. Restoring just
/// the *decisions* + *manual overrides* lets the user resume review without
/// re-doing every keep/delete call.
///
/// Cluster IDs are stable strings derived from member URLs / content hashes
/// (e.g. `"exact:<sha>"`, `"photo:<urls>"`); a re-scan that produces the same
/// cluster gets the same ID, so the persisted decisions auto-attach. New
/// files create new clusters with no persisted decisions; deleted files
/// produce orphaned entries that simply don't apply to anything.
struct SessionState: Codable {
    var decisionsByCluster: [String: ClusterDecisions] = [:]
    /// Manual overrides keyed by cluster ID, then by file path (string —
    /// URL keys don't round-trip through JSON cleanly).
    var manualOverridesByCluster: [String: [String: Decision]] = [:]

    static var defaultURL: URL {
        let dir = PurpleDedup.supportDirectoryURL
        return dir.appendingPathComponent("session-state.json")
    }

    static func load(from url: URL = defaultURL) -> SessionState {
        guard let data = try? Data(contentsOf: url) else { return SessionState() }
        do {
            return try JSONDecoder().decode(SessionState.self, from: data)
        } catch {
            // A corrupt file shouldn't block app launch; log and start fresh.
            // Most likely cause is a schema change between versions; the
            // user can always re-do their review.
            NSLog("PurpleDedup: session-state load failed (\(error.localizedDescription)) — starting empty")
            return SessionState()
        }
    }

    func save(to url: URL = defaultURL) {
        let dir = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        do {
            let data = try JSONEncoder().encode(self)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("PurpleDedup: session-state save failed — \(error.localizedDescription)")
        }
    }

    /// Convert the in-memory `[URL: Decision]` shape used by the GUI to the
    /// path-keyed shape we store on disk.
    static func encodeOverrides(_ overrides: [String: [URL: Decision]]) -> [String: [String: Decision]] {
        overrides.mapValues { dict in
            dict.reduce(into: [String: Decision]()) { $0[$1.key.path] = $1.value }
        }
    }

    /// Inverse of `encodeOverrides`. Reads path strings from disk back into
    /// URL keys for in-memory use.
    static func decodeOverrides(_ encoded: [String: [String: Decision]]) -> [String: [URL: Decision]] {
        encoded.mapValues { dict in
            dict.reduce(into: [URL: Decision]()) {
                $0[URL(fileURLWithPath: $1.key)] = $1.value
            }
        }
    }
}
