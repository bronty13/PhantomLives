import Foundation
import CloudKit
import GRDB
import MasterClipperCore

/// macOS poller for shared-zone edits originated by recipients on their
/// iPhones. Every 60s (and on app foreground), enumerates each share zone
/// in the private DB, fetches any `SharedClipEdit` records, decodes the
/// embedded `IntentEnvelope`, applies via `DatabaseService.apply(intent:)`,
/// and deletes the record on success. Idempotency is provided by the
/// existing `applied_intents` table.
///
/// Why polling: CloudKit push subscriptions need the `aps-environment`
/// entitlement + remote-notifications background mode and a delegate
/// callback. Polling is cruder but works without those, and 60s latency
/// for an external collaborator's edits is fine.
@MainActor
final class SharedZoneSync: ObservableObject {
    static let shared = SharedZoneSync()

    @Published private(set) var appliedCount: Int = 0
    @Published private(set) var lastSweepAt: Date?
    @Published private(set) var lastError: String?
    @Published private(set) var isSweeping: Bool = false

    private let container: CKContainer
    private var privateDB: CKDatabase { container.privateCloudDatabase }
    private var pollingTask: Task<Void, Never>?
    private let pollIntervalSeconds: UInt64 = 60

    private init() {
        self.container = CKContainer(identifier: SnapshotLayout.iCloudContainerID)
    }

    /// Idempotent. Start the polling loop. The first sweep runs immediately.
    func start() {
        guard pollingTask == nil else { return }
        pollingTask = Task { [weak self] in
            while !Task.isCancelled {
                await self?.sweep()
                try? await Task.sleep(nanoseconds: (self?.pollIntervalSeconds ?? 60) * 1_000_000_000)
            }
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
    }

    /// One-shot sweep — call on app foreground or after creating a share.
    func sweep() async {
        guard !isSweeping else { return }
        isSweeping = true
        defer { isSweeping = false }

        do {
            let zones = try await privateDB.allRecordZones()
            for zone in zones where zone.zoneID.zoneName.hasPrefix(CKShareSchema.zoneNamePrefix) {
                try await processZone(zoneID: zone.zoneID)
            }
            lastError = nil
            lastSweepAt = Date()
        } catch {
            lastError = "SharedZoneSync sweep failed: \(error.localizedDescription)"
        }
    }

    // MARK: - Per-zone processing

    private func processZone(zoneID: CKRecordZone.ID) async throws {
        let query = CKQuery(
            recordType: CKShareSchema.sharedClipEditRecordType,
            predicate: NSPredicate(value: true)
        )
        let result = try await privateDB.records(matching: query, inZoneWith: zoneID)
        var idsToDelete: [CKRecord.ID] = []

        for (_, recResult) in result.matchResults {
            guard case .success(let record) = recResult else { continue }
            guard let envelope = decodeEnvelope(record) else {
                // Malformed — leave it in place so the user can inspect, but
                // don't fail the sweep.
                continue
            }

            switch DatabaseService.shared.apply(intent: envelope) {
            case .applied, .alreadyApplied, .appliedWithConflict:
                idsToDelete.append(record.recordID)
                appliedCount += 1
            case .failed(let msg):
                lastError = "Shared edit apply failed for \(envelope.id.uuidString.prefix(8)): \(msg)"
                // Leave record in place for retry.
            }
        }

        if !idsToDelete.isEmpty {
            try await deleteAll(recordIDs: idsToDelete)
            // The owner-side snapshot will reflect these changes on next
            // publish — schedule one so the iPhone (own user's snapshot)
            // sees it quickly. The recipient's view updates automatically
            // because CK propagates record deletions.
            SnapshotPublisher.shared.schedulePublish()
        }
    }

    private func decodeEnvelope(_ record: CKRecord) -> IntentEnvelope? {
        guard let jsonString = record[CKShareSchema.SharedClipEditField.envelopeJson] as? String,
              let data = jsonString.data(using: .utf8) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(IntentEnvelope.self, from: data)
    }

    private func deleteAll(recordIDs: [CKRecord.ID]) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let op = CKModifyRecordsOperation(recordsToSave: nil, recordIDsToDelete: recordIDs)
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success:        cont.resume()
                case .failure(let e): cont.resume(throwing: e)
                }
            }
            privateDB.add(op)
        }
    }
}
