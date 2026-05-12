import Foundation
import GRDB
import MasterClipperCore

enum SnapshotReaderError: LocalizedError {
    case noUbiquityContainer
    case snapshotNotPresent
    case downloadTimedOut
    case openFailed(String)
    case schemaTooNew(observed: Int, supported: Int)

    var errorDescription: String? {
        switch self {
        case .noUbiquityContainer:
            return "iCloud Drive is not available. Sign in to iCloud and enable iCloud Drive in Settings."
        case .snapshotNotPresent:
            return "No snapshot has been published from your Mac yet. Open MasterClipper on your Mac and tap Publish now in Settings → Sync."
        case .downloadTimedOut:
            return "Timed out downloading the latest snapshot from iCloud."
        case .openFailed(let msg):
            return "Couldn't open the snapshot database: \(msg)"
        case .schemaTooNew(let observed, let supported):
            return "This snapshot was written by a newer version of MasterClipper (schema v\(observed)). Update the iOS app — this version only supports up to v\(supported)."
        }
    }
}

@MainActor
final class SnapshotReader: ObservableObject {

    @Published private(set) var manifest: SnapshotManifest?
    @Published private(set) var lastReloadedAt: Date?
    @Published private(set) var isLoading: Bool = false
    @Published private(set) var lastError: String?

    /// Read-only GRDB queue opened against the local cached copy of the
    /// snapshot. nil until the first successful load.
    private(set) var reader: DatabaseQueue?

    private var metadataQuery: NSMetadataQuery?

    // MARK: - Public API

    /// URL of the iCloud snapshot folder. Nil if iCloud isn't available.
    var snapshotFolderURL: URL? {
        FileManager.default
            .url(forUbiquityContainerIdentifier: SnapshotLayout.iCloudContainerID)?
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(SnapshotLayout.snapshotDir, isDirectory: true)
    }

    var snapshotDbCloudURL: URL? {
        snapshotFolderURL?.appendingPathComponent(SnapshotLayout.snapshotDbFile)
    }

    var manifestCloudURL: URL? {
        snapshotFolderURL?.appendingPathComponent(SnapshotLayout.manifestFile)
    }

    /// App-sandbox cached copy of the snapshot — we never open the iCloud file
    /// directly so iCloud-side rewrites can't yank GRDB's mmap out from under us.
    var localSnapshotDbURL: URL {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return caches.appendingPathComponent("snapshot.sqlite")
    }

    func start() async {
        installMetadataQuery()
        await reload()
    }

    func reload() async {
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }

        do {
            try await performReload()
            lastReloadedAt = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Resolve a thumbnail URL (in the iCloud snapshot's thumbnails folder)
    /// for a given clip id. Returns nil if the snapshot isn't loaded yet.
    func thumbnailURL(for clipId: String) -> URL? {
        snapshotFolderURL?
            .appendingPathComponent(SnapshotLayout.thumbnailsDir, isDirectory: true)
            .appendingPathComponent("\(clipId).jpg")
    }

    // MARK: - Reload pipeline

    private func performReload() async throws {
        guard let cloudDbURL = snapshotDbCloudURL,
              let manifestURL = manifestCloudURL,
              let folderURL = snapshotFolderURL else {
            throw SnapshotReaderError.noUbiquityContainer
        }

        let fm = FileManager.default
        let parentDir = folderURL.deletingLastPathComponent()
        // Ensure the parent Documents/ exists so the metadata query has
        // something to watch (iOS won't auto-create the ubiquity container).
        try? fm.createDirectory(at: parentDir, withIntermediateDirectories: true)

        // 1. Kick off downloads of both files (snapshot + manifest) if they're
        //    in the cloud-only state.
        try? fm.startDownloadingUbiquitousItem(at: cloudDbURL)
        try? fm.startDownloadingUbiquitousItem(at: manifestURL)

        // 2. Wait up to ~30s for both to materialize locally.
        try await waitForDownload(of: [cloudDbURL, manifestURL], timeout: 30)

        // 3. Read manifest, validate schema.
        let manifestData = try await readCoordinated(at: manifestURL)
        let decoded = try JSONDecoder().decode(SnapshotManifest.self, from: manifestData)
        if decoded.schemaVersion > SnapshotLayout.currentSchemaVersion {
            throw SnapshotReaderError.schemaTooNew(
                observed: decoded.schemaVersion,
                supported: SnapshotLayout.currentSchemaVersion
            )
        }

        // 4. Copy snapshot.sqlite into our sandbox via NSFileCoordinator.
        let dest = localSnapshotDbURL
        try? fm.removeItem(at: dest)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordError: NSError?
        var copyError: Error?
        coordinator.coordinate(readingItemAt: cloudDbURL,
                               options: .withoutChanges,
                               error: &coordError) { readURL in
            do {
                try fm.copyItem(at: readURL, to: dest)
            } catch {
                copyError = error
            }
        }
        if let err = coordError ?? (copyError as NSError?) {
            throw SnapshotReaderError.openFailed(err.localizedDescription)
        }

        // 5. Open as read-only GRDB DatabaseQueue. WAL doesn't exist on a
        //    VACUUM INTO-produced file, so a Queue (not a Pool) is correct.
        var config = Configuration()
        config.readonly = true
        let queue = try DatabaseQueue(path: dest.path, configuration: config)

        // Publish.
        self.manifest = decoded
        self.reader = queue
    }

    // MARK: - File coordination + waiting

    /// Block (asynchronously) until each URL exists locally and isn't still
    /// downloading. Polls every 0.5s.
    private func waitForDownload(of urls: [URL], timeout seconds: TimeInterval) async throws {
        let deadline = Date().addingTimeInterval(seconds)
        let fm = FileManager.default

        while Date() < deadline {
            var allReady = true
            for url in urls {
                guard fm.fileExists(atPath: url.path) else {
                    allReady = false
                    break
                }
                let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                let status = values?.ubiquitousItemDownloadingStatus
                if status != .current && status != nil {
                    allReady = false
                    break
                }
            }
            if allReady { return }
            try await Task.sleep(nanoseconds: 500_000_000)
        }

        // Check existence once more for a precise error.
        for url in urls where !fm.fileExists(atPath: url.path) {
            throw SnapshotReaderError.snapshotNotPresent
        }
        throw SnapshotReaderError.downloadTimedOut
    }

    private func readCoordinated(at url: URL) async throws -> Data {
        try await withCheckedThrowingContinuation { cont in
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordError: NSError?
            var result: Result<Data, Error> = .failure(SnapshotReaderError.openFailed("uninitialised"))
            coordinator.coordinate(readingItemAt: url,
                                   options: .withoutChanges,
                                   error: &coordError) { readURL in
                do {
                    result = .success(try Data(contentsOf: readURL))
                } catch {
                    result = .failure(error)
                }
            }
            if let err = coordError {
                cont.resume(throwing: err)
                return
            }
            cont.resume(with: result)
        }
    }

    // MARK: - NSMetadataQuery — observe new snapshots

    private func installMetadataQuery() {
        guard metadataQuery == nil else { return }
        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        // Match anything named manifest.json under our container — when the
        // Mac publishes a new snapshot, manifest.json's update fires here.
        q.predicate = NSPredicate(format: "%K LIKE %@",
                                  NSMetadataItemFSNameKey, SnapshotLayout.manifestFile)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataQueryDidUpdate(_:)),
            name: .NSMetadataQueryDidUpdate,
            object: q
        )
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(metadataQueryDidUpdate(_:)),
            name: .NSMetadataQueryDidFinishGathering,
            object: q
        )
        q.start()
        metadataQuery = q
    }

    @objc private func metadataQueryDidUpdate(_ note: Notification) {
        // Coalesce — reload on any change.
        Task { @MainActor in
            await self.reload()
        }
    }
}
