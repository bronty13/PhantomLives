import Foundation
import GRDB
import MasterClipperCore

enum SnapshotPublisherError: LocalizedError {
    case noUbiquityContainer
    case publishFailed(String)

    var errorDescription: String? {
        switch self {
        case .noUbiquityContainer:
            return "iCloud Drive is not available. Confirm you're signed in to iCloud and that the MasterClipper iCloud container is enabled in System Settings → Apple ID → iCloud → iCloud Drive."
        case .publishFailed(let msg):
            return "Snapshot publish failed: \(msg)"
        }
    }
}

@MainActor
final class SnapshotPublisher: ObservableObject {
    static let shared = SnapshotPublisher()

    @Published private(set) var lastPublishedAt: Date?
    @Published private(set) var lastSnapshotSize: Int64?
    @Published private(set) var lastClipCount: Int = 0
    @Published private(set) var lastThumbnailCount: Int = 0
    @Published private(set) var isPublishing: Bool = false
    @Published private(set) var lastError: String?

    /// 30-second quiet period after a mutation before we actually publish.
    /// Calling `schedulePublish()` repeatedly within the window collapses to a
    /// single publish at the end.
    private let debounceSeconds: UInt64 = 30
    private var debounceTask: Task<Void, Never>?

    private init() {}

    // MARK: - Public surface

    var ubiquityContainer: URL? {
        FileManager.default.url(forUbiquityContainerIdentifier: SnapshotLayout.iCloudContainerID)
    }

    var snapshotFolderURL: URL? {
        ubiquityContainer?
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(SnapshotLayout.snapshotDir, isDirectory: true)
    }

    /// Coalesced publish — re-arms a 30s timer on every call. Use after any
    /// mutation that should eventually surface on iOS (clip create/update,
    /// posting change, note add).
    func schedulePublish() {
        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: (self?.debounceSeconds ?? 30) * 1_000_000_000)
            guard !Task.isCancelled else { return }
            await self?.publishNow()
        }
    }

    /// Immediate publish — for the "Publish now" button and on terminate.
    /// Safe to call concurrently: a second call while one is in flight no-ops.
    func publishNow() async {
        guard !isPublishing else { return }
        isPublishing = true
        defer { isPublishing = false }

        do {
            try await performPublish()
            lastPublishedAt = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Implementation

    private func performPublish() async throws {
        guard let snapshotURL = snapshotFolderURL else {
            throw SnapshotPublisherError.noUbiquityContainer
        }
        let parentDir = snapshotURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: parentDir, withIntermediateDirectories: true)

        let pool = DatabaseService.shared.dbPool
        let publisherID = SnapshotPublisher.publisherDeviceId()

        // 1. Gather list of (clipId, sourceThumbnailURL) on the main actor.
        let thumbnailJobs = try await pool.read { db -> [(clipId: String, source: URL)] in
            let clips = try Clip.fetchAll(db)
            return clips.compactMap { clip in
                guard
                    let folder = clip.productionFolder, !folder.isEmpty,
                    let filename = clip.thumbnailFilename, !filename.isEmpty
                else { return nil }
                let expanded = (folder as NSString).expandingTildeInPath
                let src = URL(fileURLWithPath: expanded).appendingPathComponent(filename)
                return (clipId: clip.id, source: src)
            }
        }
        let clipCount = try await pool.read { db in try Clip.fetchCount(db) }

        // 2. Heavy work off main. The pool is thread-safe; clip-list snapshot
        //    is immutable; only the filesystem + sqlite write happens here.
        let tmpDir = parentDir.appendingPathComponent(SnapshotLayout.snapshotTmpDir, isDirectory: true)
        try await Task.detached(priority: .utility) {
            try Self.writeSnapshot(
                pool: pool,
                tmpDir: tmpDir,
                finalDir: snapshotURL,
                thumbnailJobs: thumbnailJobs,
                clipCount: clipCount,
                publisherID: publisherID
            )
        }.value

        lastSnapshotSize = (try? Self.folderSize(at: snapshotURL)) ?? nil
        lastClipCount = clipCount
        lastThumbnailCount = thumbnailJobs.count
    }

    // MARK: - Heavy work (off main)

    nonisolated private static func writeSnapshot(
        pool: DatabasePool,
        tmpDir: URL,
        finalDir: URL,
        thumbnailJobs: [(clipId: String, source: URL)],
        clipCount: Int,
        publisherID: String
    ) throws {
        let fm = FileManager.default

        // Fresh tmpDir each run — easier than diffing.
        if fm.fileExists(atPath: tmpDir.path) {
            try fm.removeItem(at: tmpDir)
        }
        try fm.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        // 1. VACUUM INTO the staging file. VACUUM INTO cannot run inside a
        //    transaction, so use writeWithoutTransaction.
        let dbDest = tmpDir.appendingPathComponent(SnapshotLayout.snapshotDbFile)
        try pool.writeWithoutTransaction { db in
            try db.execute(sql: "VACUUM INTO ?", arguments: [dbDest.path])
        }

        // 2. Copy thumbnails. Missing sources are skipped (not fatal).
        let thumbsDir = tmpDir.appendingPathComponent(SnapshotLayout.thumbnailsDir, isDirectory: true)
        try fm.createDirectory(at: thumbsDir, withIntermediateDirectories: true)
        var copiedCount = 0
        for job in thumbnailJobs {
            guard fm.fileExists(atPath: job.source.path) else { continue }
            let dest = thumbsDir.appendingPathComponent("\(job.clipId).jpg")
            do {
                try fm.copyItem(at: job.source, to: dest)
                copiedCount += 1
            } catch {
                // Best-effort. A failed copy on one clip doesn't abort the publish.
                continue
            }
        }

        // 3. Write manifest.
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let manifest = SnapshotManifest(
            schemaVersion: SnapshotLayout.currentSchemaVersion,
            generatedAt: iso.string(from: Date()),
            clipCount: clipCount,
            thumbnailCount: copiedCount,
            publisherDeviceId: publisherID,
            minIosSchemaVersion: SnapshotLayout.minIosSchemaVersion
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let manifestData = try encoder.encode(manifest)
        let manifestURL = tmpDir.appendingPathComponent(SnapshotLayout.manifestFile)
        try manifestData.write(to: manifestURL, options: .atomic)

        // 4. Atomic swap into place via NSFileCoordinator. If a previous
        //    snapshot exists we move it aside then remove it; if not we move
        //    the tmp dir straight into place.
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordError: NSError?
        var swapError: Error?
        coordinator.coordinate(writingItemAt: finalDir,
                               options: .forReplacing,
                               error: &coordError) { coordinatedURL in
            do {
                if fm.fileExists(atPath: coordinatedURL.path) {
                    // replaceItemAt requires the dest to exist; it atomically
                    // swaps in the contents of tmpDir.
                    _ = try fm.replaceItemAt(coordinatedURL, withItemAt: tmpDir)
                } else {
                    try fm.moveItem(at: tmpDir, to: coordinatedURL)
                }
            } catch {
                swapError = error
            }
        }
        if let err = coordError ?? (swapError as NSError?) {
            // Best-effort cleanup of tmpDir if the swap failed.
            try? fm.removeItem(at: tmpDir)
            throw SnapshotPublisherError.publishFailed(err.localizedDescription)
        }
    }

    // MARK: - Helpers

    /// Computes the on-disk size of the snapshot folder. Best-effort — returns
    /// nil if iCloud has evicted the file and replaced it with a stub.
    nonisolated private static func folderSize(at url: URL) throws -> Int64 {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: url,
                                             includingPropertiesForKeys: [.totalFileAllocatedSizeKey],
                                             options: [.skipsHiddenFiles]) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize {
                total += Int64(size)
            }
        }
        return total
    }

    /// Stable per-Mac identifier; survives hostname changes by living in
    /// UserDefaults under our own key.
    private static func publisherDeviceId() -> String {
        let key = "MasterClipper.publisherDeviceId"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let host = Host.current().localizedName ?? "mac"
        let id = "\(host.replacingOccurrences(of: " ", with: "-"))-\(UUID().uuidString.prefix(8))"
        UserDefaults.standard.set(id, forKey: key)
        return id
    }
}
