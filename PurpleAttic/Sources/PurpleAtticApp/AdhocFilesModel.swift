import Foundation
import Combine
import AppKit
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
    /// Selected row id (= path) for the management actions.
    @Published var selection: String? = nil
    /// True while a rename / delete / export is in flight (disables the action buttons).
    @Published var isMutating = false

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

    // MARK: - Management (rename / delete)

    /// Rename/move an object within the store (server-side; no re-upload). On success the cache is
    /// updated in place (old path removed, new path put) so the table reflects it without a re-list.
    func rename(config: AdhocBackupConfig, file: AdhocFile, toPath rawNew: String,
                completion: @escaping (Bool) -> Void) {
        guard !isMutating else { return }
        let newPath = rawNew.trimmingCharacters(in: CharacterSet(charactersIn: " /"))
        guard !newPath.isEmpty, newPath != file.path else { completion(false); return }
        isMutating = true
        lastError = nil
        statusMessage = nil
        let cache = self.cache
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = RcloneService.rename(config: config, from: file.path, to: newPath)
            var ok = false, msg: String? = nil, err: String? = nil
            switch outcome {
            case .ok:
                ok = true
                msg = "Renamed to \(newPath)"
                if let cache {
                    try? cache.remove(path: file.path)
                    try? cache.put(AdhocFile(path: newPath, name: (newPath as NSString).lastPathComponent,
                                             size: file.size, modTime: file.modTime, isDir: file.isDir,
                                             mimeType: file.mimeType, sha1: file.sha1,
                                             remoteID: file.remoteID, tier: file.tier, lastSeen: Date()))
                }
            case .skipped(let r): err = "Skipped — \(r)"
            case .failed(let d): err = d
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isMutating = false
                if ok, let cache { self.files = (try? cache.allFiles()) ?? self.files; self.selection = newPath }
                self.statusMessage = msg
                self.lastError = err
                completion(ok)
            }
        }
    }

    /// **Permanently** delete an object (hard delete; unrecoverable). On success the row is removed
    /// from the cache locally so the table updates immediately (avoiding B2's brief eventual-consistency
    /// window where a re-list could still show it).
    func delete(config: AdhocBackupConfig, file: AdhocFile, completion: @escaping (Bool) -> Void) {
        guard !isMutating else { return }
        isMutating = true
        lastError = nil
        statusMessage = nil
        let cache = self.cache
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let outcome = RcloneService.delete(config: config, path: file.path)
            var ok = false, msg: String? = nil, err: String? = nil
            switch outcome {
            case .ok:
                ok = true
                msg = "Permanently deleted \(file.name)"
                if let cache { try? cache.remove(path: file.path) }
            case .skipped(let r): err = "Skipped — \(r)"
            case .failed(let d): err = d
            }
            DispatchQueue.main.async {
                guard let self else { return }
                self.isMutating = false
                if ok, let cache { self.files = (try? cache.allFiles()) ?? self.files; self.selection = nil }
                self.statusMessage = msg
                self.lastError = err
                completion(ok)
            }
        }
    }

    // MARK: - Report export

    /// Render the current cached listing to a report file in ~/Downloads/PurpleAttic/ and reveal it.
    func exportReport(format: AdhocReport.Format) {
        let files = self.files
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let now = Date()
            let content = AdhocReport.render(files, format: format, generatedAt: now)
            let dir = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads/PurpleAttic")
            let stamp: String = {
                let f = DateFormatter(); f.dateFormat = "yyyyMMdd-HHmmss"; return f.string(from: now)
            }()
            let url = dir.appendingPathComponent("adhoc-b2-report-\(stamp).\(format.ext)")
            do {
                try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                try content.write(to: url, atomically: true, encoding: .utf8)
                DispatchQueue.main.async {
                    self?.statusMessage = "Report saved to \(url.path)"
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            } catch {
                DispatchQueue.main.async { self?.lastError = "Couldn't write report: \(error.localizedDescription)" }
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
