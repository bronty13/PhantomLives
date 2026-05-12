import Foundation
import MasterClipperCore

/// Watches `intents/pending/` in the iCloud ubiquity container for new
/// envelopes written by the iOS app. Decodes each one, calls
/// `DatabaseService.apply(intent:)`, then moves the file into
/// `intents/applied/` (or `intents/conflicts/` if `applyResult ==
/// .appliedWithConflict`). Triggers a snapshot publish afterward so the
/// iPhone sees the result quickly.
@MainActor
final class IntentInbox: ObservableObject {
    static let shared = IntentInbox()

    @Published private(set) var appliedCount: Int = 0
    @Published private(set) var conflictCount: Int = 0
    @Published private(set) var lastAppliedAt: Date?
    @Published private(set) var lastError: String?

    private var metadataQuery: NSMetadataQuery?
    private var isProcessing = false
    private var started = false

    private init() {}

    /// Begin watching iCloud for new intents. Idempotent.
    func start() {
        guard !started else { return }
        started = true

        // Initial sweep — pick up anything that may have arrived while the
        // app was closed.
        Task { await self.processPendingFolder() }

        installMetadataQuery()
    }

    private func installMetadataQuery() {
        guard metadataQuery == nil else { return }
        let q = NSMetadataQuery()
        q.searchScopes = [NSMetadataQueryUbiquitousDocumentsScope]
        // Match *.json files under intents/pending/. NSMetadataQuery doesn't
        // support folder filtering directly, so we match by filename suffix
        // and filter the path in the handler.
        q.predicate = NSPredicate(format: "%K LIKE %@",
                                  NSMetadataItemFSNameKey, "*.json")
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
        Task { await self.processPendingFolder() }
    }

    // MARK: - Processing

    private func processPendingFolder() async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }

        guard let container = FileManager.default.url(
                forUbiquityContainerIdentifier: SnapshotLayout.iCloudContainerID) else {
            return
        }

        let pendingDir = IntentLayout.pendingDirURL(in: container)
        let appliedDir = IntentLayout.appliedDirURL(in: container)
        let conflictsDir = IntentLayout.conflictsDirURL(in: container)
        try? FileManager.default.createDirectory(at: pendingDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: appliedDir, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: conflictsDir, withIntermediateDirectories: true)

        let fm = FileManager.default
        let files: [URL]
        do {
            files = try fm.contentsOfDirectory(at: pendingDir,
                                               includingPropertiesForKeys: [.isRegularFileKey],
                                               options: [.skipsHiddenFiles])
                .filter { $0.pathExtension.lowercased() == "json" }
        } catch {
            // Folder may not exist yet — first run, no intents ever written.
            return
        }

        guard !files.isEmpty else { return }

        var didApply = false
        for fileURL in files {
            // Make sure the file is materialised locally before reading.
            try? fm.startDownloadingUbiquitousItem(at: fileURL)

            guard let envelope = await readEnvelope(at: fileURL) else { continue }

            let result = DatabaseService.shared.apply(intent: envelope)
            switch result {
            case .applied, .alreadyApplied:
                _ = moveFile(fileURL, into: appliedDir)
                appliedCount += 1
                didApply = true
            case .appliedWithConflict(let detail):
                _ = moveFile(fileURL, into: conflictsDir)
                writeConflictSidecar(for: fileURL, detail: detail, into: conflictsDir)
                conflictCount += 1
                didApply = true
            case .failed(let msg):
                lastError = "Intent \(envelope.id.uuidString.prefix(8)) failed: \(msg)"
                // Leave the file in place so we can retry on next pass.
            }
        }

        if didApply {
            lastAppliedAt = Date()
            // Trigger a snapshot publish so the iPhone sees the result.
            SnapshotPublisher.shared.schedulePublish()
        }
    }

    // MARK: - File coordination

    private func readEnvelope(at url: URL) async -> IntentEnvelope? {
        // Wait briefly for download to complete if it's still progressing.
        let fm = FileManager.default
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            if fm.fileExists(atPath: url.path) {
                let values = try? url.resourceValues(forKeys: [.ubiquitousItemDownloadingStatusKey])
                let status = values?.ubiquitousItemDownloadingStatus
                if status == .current || status == nil { break }
            }
            try? await Task.sleep(nanoseconds: 300_000_000)
        }
        guard fm.fileExists(atPath: url.path) else { return nil }

        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordError: NSError?
        var data: Data?
        coordinator.coordinate(readingItemAt: url,
                               options: .withoutChanges,
                               error: &coordError) { readURL in
            data = try? Data(contentsOf: readURL)
        }
        guard let payload = data else { return nil }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(IntentEnvelope.self, from: payload)
        } catch {
            lastError = "Decode failed for \(url.lastPathComponent): \(error.localizedDescription)"
            return nil
        }
    }

    @discardableResult
    private func moveFile(_ source: URL, into folder: URL) -> URL? {
        let dest = folder.appendingPathComponent(source.lastPathComponent)
        let fm = FileManager.default
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordError: NSError?
        var moveError: Error?

        coordinator.coordinate(
            writingItemAt: source, options: .forMoving,
            writingItemAt: dest, options: .forReplacing,
            error: &coordError) { srcURL, destURL in
                do {
                    if fm.fileExists(atPath: destURL.path) {
                        try fm.removeItem(at: destURL)
                    }
                    try fm.moveItem(at: srcURL, to: destURL)
                } catch {
                    moveError = error
                }
            }

        if coordError != nil || moveError != nil { return nil }
        return dest
    }

    private func writeConflictSidecar(for sourceFile: URL, detail: String, into folder: URL) {
        let sidecar = folder
            .appendingPathComponent("\(sourceFile.deletingPathExtension().lastPathComponent).conflict.txt")
        let body = """
        Conflict detected at \(DatabaseService.isoNow())
        Source: \(sourceFile.lastPathComponent)
        Detail: \(detail)
        """
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordError: NSError?
        coordinator.coordinate(writingItemAt: sidecar,
                               options: .forReplacing,
                               error: &coordError) { writeURL in
            try? body.write(to: writeURL, atomically: true, encoding: .utf8)
        }
    }
}
