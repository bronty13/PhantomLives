import Foundation
import CloudKit
import MasterClipperCore

/// iOS-side helper that lets a read-write recipient mutate the clips they've
/// been shared. Each edit composes an `IntentEnvelope` (same envelope the
/// user's own iCloud-Drive intent outbox writes), JSON-encodes it, and
/// writes a `SharedClipEdit` CKRecord into the share's zone via
/// `sharedCloudDatabase`. The Mac's `SharedZoneSync` poller picks it up and
/// routes it through `DatabaseService.apply(intent:)`.
@MainActor
final class SharedZoneEditor: ObservableObject {

    /// Intent ids the recipient has submitted but hasn't seen confirmed yet.
    /// Keyed by clipId for fast lookups in the detail view.
    @Published private(set) var pendingByClipId: [String: [UUID]] = [:]
    @Published private(set) var lastError: String?
    @Published private(set) var inFlight: Bool = false

    private let container: CKContainer
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }
    private let reader: SharedZoneReader

    init(reader: SharedZoneReader) {
        self.container = CKContainer(identifier: SnapshotLayout.iCloudContainerID)
        self.reader = reader
    }

    // MARK: - Public submission API (mirrors IntentOutbox)

    @discardableResult
    func submitMarkPosted(in session: SharedShareSession, clipId: String, siteCode: String, date: Date = Date()) async -> Bool {
        await submit(
            session: session, clipId: clipId,
            kind: .markPosted,
            payload: .markPosted(siteCode: siteCode, postedDate: Self.isoDate(date))
        )
    }

    @discardableResult
    func submitUnmarkPosted(in session: SharedShareSession, clipId: String, siteCode: String) async -> Bool {
        await submit(
            session: session, clipId: clipId,
            kind: .unmarkPosted,
            payload: .unmarkPosted(siteCode: siteCode)
        )
    }

    @discardableResult
    func submitAddNote(in session: SharedShareSession, clipId: String, body: String, operatorName: String) async -> Bool {
        await submit(
            session: session, clipId: clipId,
            kind: .addNote,
            payload: .addNote(body: body, operatorName: operatorName)
        )
    }

    @discardableResult
    func submitSetStatus(in session: SharedShareSession, clipId: String, status: String?) async -> Bool {
        await submit(
            session: session, clipId: clipId,
            kind: .setStatus,
            payload: .setStatus(status: status)
        )
    }

    @discardableResult
    func submitTogglePostingExcluded(in session: SharedShareSession, clipId: String, excluded: Bool, reason: String, notes: String) async -> Bool {
        await submit(
            session: session, clipId: clipId,
            kind: .togglePostingExcluded,
            payload: .togglePostingExcluded(excluded: excluded, reason: reason, notes: notes)
        )
    }

    func hasPending(forClip clipId: String) -> Bool {
        !(pendingByClipId[clipId]?.isEmpty ?? true)
    }

    /// Drop pending entries that no longer appear in the next refresh.
    /// Called from `iOSAppState` after `SharedZoneReader.refresh()` so we can
    /// clear locally-tracked UUIDs once the Mac has processed (and deleted)
    /// the corresponding CKRecord. We don't fetch CK delete tombstones — we
    /// just clear after a short window.
    func reconcilePendingAfterRefresh() {
        // Best-effort cleanup: anything older than 5 minutes assumed processed.
        // The Mac deletes the SharedClipEdit record on apply, but the
        // recipient device doesn't see the deletion directly. Time-based
        // expiry is simpler than maintaining a CKQuery against the shared DB.
        let staleCutoff = Date().addingTimeInterval(-300)
        var changed = false
        for (clipId, ids) in pendingByClipId {
            let kept = ids.compactMap { id -> UUID? in
                guard let timestamp = pendingTimestamps[id] else { return id }
                return timestamp > staleCutoff ? id : nil
            }
            if kept.count != ids.count { changed = true }
            if kept.isEmpty { pendingByClipId.removeValue(forKey: clipId) }
            else { pendingByClipId[clipId] = kept }
        }
        if changed {
            // Also prune the timestamps map.
            pendingTimestamps = pendingTimestamps.filter { $0.value > staleCutoff }
        }
    }

    // MARK: - Internals

    private var pendingTimestamps: [UUID: Date] = [:]

    private func submit(
        session: SharedShareSession,
        clipId: String,
        kind: IntentKind,
        payload: IntentPayload
    ) async -> Bool {
        inFlight = true
        defer { inFlight = false }

        let envelope = IntentEnvelope(
            kind: kind,
            clipId: clipId,
            payload: payload,
            deviceId: Self.deviceId(),
            // No snapshot of the Mac's DB on a shared recipient; mark the
            // base as the share's creation time. Mac's conflict policy is
            // last-writer-wins anyway, so this is informational only.
            baseSnapshotGeneratedAt: Self.iso(session.metadata.createdAt),
            appVersion: Self.appVersion()
        )

        do {
            let data = try Self.jsonEncoder.encode(envelope)
            guard let jsonString = String(data: data, encoding: .utf8) else {
                throw NSError(domain: "SharedZoneEditor",
                              code: 1,
                              userInfo: [NSLocalizedDescriptionKey: "Could not encode envelope"])
            }
            // Pull the live zoneID from the reader — its ownerName is the
            // share owner's CKUserRecordID name, which we can't reconstruct
            // ourselves.
            guard let zoneID = reader.zoneIDByShare[session.id] else {
                throw NSError(domain: "SharedZoneEditor", code: 2,
                              userInfo: [NSLocalizedDescriptionKey: "Share zone not loaded — refresh and retry."])
            }
            let recordID = CKRecord.ID(recordName: envelope.id.uuidString, zoneID: zoneID)
            let record = CKRecord(recordType: CKShareSchema.sharedClipEditRecordType, recordID: recordID)
            record[CKShareSchema.SharedClipEditField.envelopeJson] = jsonString as CKRecordValue
            record[CKShareSchema.SharedClipEditField.intentId]     = envelope.id.uuidString as CKRecordValue
            record[CKShareSchema.SharedClipEditField.clipId]       = clipId as CKRecordValue
            record[CKShareSchema.SharedClipEditField.createdAt]    = envelope.createdAt as CKRecordValue

            try await saveRecord(record)

            pendingByClipId[clipId, default: []].append(envelope.id)
            pendingTimestamps[envelope.id] = Date()
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func saveRecord(_ record: CKRecord) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let op = CKModifyRecordsOperation(recordsToSave: [record], recordIDsToDelete: nil)
            op.savePolicy = .changedKeys
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success:        cont.resume()
                case .failure(let e): cont.resume(throwing: e)
                }
            }
            sharedDB.add(op)
        }
    }

    // MARK: - Helpers

    private static let jsonEncoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        e.outputFormatting = [.sortedKeys]
        return e
    }()

    private static func deviceId() -> String {
        UserDefaults.standard.string(forKey: "MasterClipperiOS.deviceId") ?? "ios"
    }

    private static func appVersion() -> String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(v) (\(b))"
    }

    private static func isoDate(_ date: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.string(from: date)
    }

    private static func iso(_ date: Date) -> String {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f.string(from: date)
    }
}
