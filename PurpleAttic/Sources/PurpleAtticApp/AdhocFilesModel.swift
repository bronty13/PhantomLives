import Foundation
import Combine
import PurpleAtticCore

/// View-model for the **Ad-hoc Files** pane. Owns the local GRDB listing cache so the browse table
/// is instant and offline; a Refresh reconciles it with B2 via `rclone lsjson`. Network/DB work runs
/// off-main and republishes on main, mirroring the other PurpleAttic view-models.
final class AdhocFilesModel: ObservableObject {

    @Published var files: [AdhocFile] = []
    @Published var isRefreshing = false
    @Published var statusMessage: String? = nil
    @Published var lastError: String? = nil
    @Published var searchText = ""

    /// The on-disk cache (Application Support). nil only if it couldn't be opened, in which case the
    /// pane still works by showing the live listing directly (just not persisted between launches).
    private let cache: AdhocCacheStore? = try? AdhocCacheStore()

    /// Show whatever's already cached — called on appear so the table is populated with zero latency.
    func loadCached() {
        guard let cache else { return }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let all = (try? cache.allFiles()) ?? []
            DispatchQueue.main.async { self?.files = all }
        }
    }

    /// Re-list the remote and reconcile the cache (upsert + prune), then republish.
    func refresh(config: AdhocBackupConfig) {
        guard !isRefreshing else { return }
        isRefreshing = true
        lastError = nil
        statusMessage = nil
        let cache = self.cache
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let (remote, outcome) = RcloneService.list(config: config)
            var all: [AdhocFile] = []
            var msg: String? = nil
            var err: String? = nil
            switch outcome {
            case .ok(let d):
                msg = "Refreshed — \(d)"
                if let cache {
                    try? cache.replaceFromListing(remote, refreshedAt: Date())
                    all = (try? cache.allFiles()) ?? []
                } else {
                    all = remote.map { AdhocFile(remote: $0, lastSeen: Date()) }
                }
            case .skipped(let r):
                err = "Can't refresh — \(r)"
                if let cache { all = (try? cache.allFiles()) ?? [] }
            case .failed(let d):
                err = d
                if let cache { all = (try? cache.allFiles()) ?? [] }
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.files = all
                self.isRefreshing = false
                self.statusMessage = msg
                self.lastError = err
            }
        }
    }

    /// Case-insensitive name/path filter for the search box.
    var filtered: [AdhocFile] {
        let q = searchText.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !q.isEmpty else { return files }
        return files.filter { $0.path.lowercased().contains(q) || $0.name.lowercased().contains(q) }
    }

    var totalBytes: Int64 { files.reduce(0) { $0 + max(0, $1.size) } }
}
