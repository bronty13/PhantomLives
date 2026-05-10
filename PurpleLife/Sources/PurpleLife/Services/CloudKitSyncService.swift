import CloudKit
import Foundation
import GRDB
import SwiftUI

/// Phase 4 — multi-Mac CloudKit sync.
///
/// Mirrors every `ObjectRecord` to the user's private CloudKit database
/// in a custom zone (`PurpleLifeZone`). The encryption layer uses
/// `CKRecord.encryptedValues["fieldsJSON"]` — the same shape the
/// `Spike/CloudKit` PASS validated on 2026-05-10. Plaintext columns
/// (`type_id`, `parent_id`, `created_at`, `updated_at`) live in the
/// regular `record[...]` slots so server-side queries / conflict
/// resolution can read them without keys.
///
/// Phase 4 acceptance gate per `PLAN.md`:
/// - typical edit syncs Mac→Mac in <5s ← push-on-mutation + 30s poll
/// - same-field offline edit reconciles deterministically ← LWW by
///   `updated_at`
/// - dashboard shows encrypted fields as opaque ← provided by
///   `encryptedValues`
///
/// Sync arrives via two paths:
///
/// 1. **Silent-push wakeups** (primary). A `CKDatabaseSubscription`
///    registered on bootstrap fires whenever any record in the private
///    database changes on another device. APNS delivers a content-only
///    push to `AppDelegate`, which posts a `NotificationCenter` event;
///    this service observes it and triggers a `pull()` immediately.
///    Sub-second Mac→Mac in the typical case.
///
/// 2. **Recovery poll** (fallback). A 5-min foreground task runs `pull()`
///    in case a silent push was missed (offline, sleep, dropped APNS),
///    keeping the gap bounded even when push delivery isn't reliable.
@MainActor
final class CloudKitSyncService: ObservableObject {

    static let containerID = "iCloud.com.bronty13.PurpleLife"
    static let recordType = "PurpleObject"
    static let typeRecordType = "PurpleType"
    static let zoneName = "PurpleLifeZone"
    static let subscriptionID = "PurpleLife.databaseSubscription"
    /// Recovery poll. The primary sync trigger is the
    /// CKDatabaseSubscription silent push; this only catches up if a
    /// push was dropped (offline, APNS hiccup, app slept through it).
    static let pollSeconds: UInt64 = 300

    private static let subscriptionRegisteredKey = "PurpleLife.subscriptionRegistered"

    enum Status: Equatable {
        case disabled                 // entitlements/container unavailable; staying local-only
        case notSignedIn
        case settingUp
        case idle
        case syncing
        case error(String)

        var isError: Bool {
            if case .error = self { return true } else { return false }
        }

        var label: String {
            switch self {
            case .disabled:    return "Sync off"
            case .notSignedIn: return "Sign in to iCloud"
            case .settingUp:   return "Setting up sync…"
            case .idle:        return "Synced"
            case .syncing:     return "Syncing…"
            case .error(let m): return "Sync error: \(m)"
            }
        }

        var systemImage: String {
            switch self {
            case .disabled:    return "icloud.slash"
            case .notSignedIn: return "person.crop.circle.badge.exclamationmark"
            case .settingUp:   return "icloud.and.arrow.down.fill"
            case .idle:        return "checkmark.icloud.fill"
            case .syncing:     return "arrow.triangle.2.circlepath.icloud"
            case .error:       return "exclamationmark.icloud.fill"
            }
        }
    }

    @Published private(set) var status: Status = .settingUp
    @Published private(set) var lastSyncAt: Date?
    @Published private(set) var lastError: String?

    private weak var schema: SchemaRegistry?
    // Lazily constructed — `CKContainer(identifier:)` traps when the
    // app is signed without the iCloud entitlement (e.g. under XCTest
    // with the no-iCloud override). Building the container only when
    // we're actually about to talk to CloudKit lets the local-only
    // codepath run anywhere.
    private var container: CKContainer?
    private var database: CKDatabase? { container?.privateCloudDatabase }
    private let zoneID = CKRecordZone.ID(zoneName: CloudKitSyncService.zoneName,
                                         ownerName: CKCurrentUserDefaultName)

    private var pollTask: Task<Void, Never>?
    private var inFlight = false
    private var pushObserver: NSObjectProtocol?

    // Server change token — resumes incremental sync across launches.
    private static let tokenKey = "PurpleLife.serverChangeToken"
    private var serverChangeToken: CKServerChangeToken? {
        get {
            guard let data = UserDefaults.standard.data(forKey: Self.tokenKey),
                  let token = try? NSKeyedUnarchiver.unarchivedObject(
                      ofClass: CKServerChangeToken.self, from: data
                  ) else { return nil }
            return token
        }
        set {
            if let token = newValue,
               let data = try? NSKeyedArchiver.archivedData(
                   withRootObject: token, requiringSecureCoding: true
               ) {
                UserDefaults.standard.set(data, forKey: Self.tokenKey)
            } else {
                UserDefaults.standard.removeObject(forKey: Self.tokenKey)
            }
        }
    }

    // MARK: - Lifecycle

    func start(schema: SchemaRegistry) {
        self.schema = schema
        observePushNotifications()
        Task { await bootstrap() }
    }

    func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    deinit {
        if let pushObserver {
            NotificationCenter.default.removeObserver(pushObserver)
        }
    }

    /// Subscribe to the silent-push event posted by `AppDelegate`. The
    /// observer lives for the service's lifetime; cleaned up in `deinit`.
    private func observePushNotifications() {
        guard pushObserver == nil else { return }
        pushObserver = NotificationCenter.default.addObserver(
            forName: AppDelegate.didReceiveCloudKitPushNotification,
            object: nil,
            queue: .main
        ) { [weak self] note in
            let userInfo = (note.userInfo as? [String: Any]) ?? [:]
            Task { @MainActor [weak self] in
                self?.handleSubscriptionNotification(userInfo: userInfo)
            }
        }
    }

    /// Called when AppDelegate forwards a CloudKit silent push.
    /// Returns whether the userInfo was recognized as a CK notification —
    /// the bool is for the unit tests; the side effect (a `pull()`) is
    /// what the running app cares about.
    @discardableResult
    func handleSubscriptionNotification(userInfo: [String: Any]) -> Bool {
        guard let cloudKitNote = CKNotification(fromRemoteNotificationDictionary: userInfo) else {
            return false
        }
        // We only registered one subscription, so the subscription ID
        // check is more of a sanity guard than a router. Kept defensive
        // — if Apple ever lights up additional subscriptions for the
        // container (shared DB, file provider, etc.), an unrelated push
        // shouldn't trigger a pull on every wakeup.
        if let subID = cloudKitNote.subscriptionID, subID != Self.subscriptionID {
            return false
        }
        Task { await pull() }
        return true
    }

    /// Trigger a one-shot pull (idempotent; ignores if a sync is already
    /// running). Public so the user can hit a "Sync now" button later.
    func syncNow() {
        Task { await pull() }
    }

    private func bootstrap() async {
        status = .settingUp
        // Construct the container here, inside a do/catch — this is the
        // first place that requires the iCloud entitlement. If it's
        // missing the framework traps (not throws); we can't catch a
        // SIGTRAP, so the entitlement must be present at this point or
        // the host app would have crashed at launch already. This step
        // is a sanity check; the failure mode we *can* handle is a
        // bad-container or missing-entitlement CKError from a
        // downstream operation.
        container = CKContainer(identifier: Self.containerID)
        do {
            try await checkAccountStatus()
            try await ensureZone()
            await ensureSubscription()
            await pullInitial()
            await pushPendingLocalChanges()
            status = .idle
            startPolling()
        } catch let error as CKError where error.code == .badContainer
                                       || error.code == .missingEntitlement {
            // App ID isn't provisioned for this container yet, or the
            // entitlements file doesn't include iCloud. Fall back to
            // local-only — the app is still fully usable.
            status = .disabled
            NSLog("PurpleLife: CloudKit sync disabled — \(error.localizedDescription)")
        } catch {
            status = .error(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    private func checkAccountStatus() async throws {
        guard let container else { throw CKError(.internalError) }
        let s = try await container.accountStatus()
        switch s {
        case .available:
            return
        case .noAccount:
            status = .notSignedIn
            throw CKError(.notAuthenticated)
        case .restricted, .couldNotDetermine, .temporarilyUnavailable:
            throw CKError(.networkUnavailable)
        @unknown default:
            throw CKError(.internalError)
        }
    }

    private func ensureZone() async throws {
        // Idempotent: CKModifyRecordZonesOperation succeeds if the zone
        // already exists.
        guard let database else { throw CKError(.internalError) }
        let zone = CKRecordZone(zoneID: zoneID)
        _ = try await database.modifyRecordZones(saving: [zone], deleting: [])
    }

    /// Register a `CKDatabaseSubscription` so APNS wakes us when another
    /// device writes a record to the private database. UserDefaults
    /// flag prevents re-saving on every launch (CloudKit accepts the
    /// duplicate save, but it's a wasted round-trip).
    ///
    /// Failures are non-fatal: the recovery poll keeps sync working
    /// without push. We log and continue rather than blocking bootstrap.
    private func ensureSubscription() async {
        guard let database else { return }
        if UserDefaults.standard.bool(forKey: Self.subscriptionRegisteredKey) { return }

        let subscription = CKDatabaseSubscription(subscriptionID: Self.subscriptionID)
        let info = CKSubscription.NotificationInfo()
        // Silent push: no UI, no user permission needed. The whole point
        // is to wake the app and let it pull — the user's reaction comes
        // from seeing the synced record appear, not from a notification.
        info.shouldSendContentAvailable = true
        subscription.notificationInfo = info

        do {
            _ = try await database.save(subscription)
            UserDefaults.standard.set(true, forKey: Self.subscriptionRegisteredKey)
        } catch let error as CKError where error.code == .serverRejectedRequest {
            // Already exists — accept it as success and remember that.
            UserDefaults.standard.set(true, forKey: Self.subscriptionRegisteredKey)
        } catch {
            NSLog("PurpleLife: subscription registration failed — \(error.localizedDescription). "
                  + "Falling back to recovery poll only.")
        }
    }

    private func startPolling() {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: Self.pollSeconds * 1_000_000_000)
                if Task.isCancelled { return }
                await self?.pull()
            }
        }
    }

    // MARK: - Push

    /// Mirror a local create/update to CloudKit. Called from
    /// `ObjectEngine.create / update`. Errors are logged but don't
    /// surface to the caller — the local write already succeeded;
    /// sync errors retry on the next poll.
    func push(record: ObjectRecord) async {
        guard isEnabled, let database else { return }
        do {
            let ck = try await fetchOrMake(record: record)
            applyLocal(record: record, to: ck)
            _ = try await database.save(ck)
            lastSyncAt = Date()
            if status.isError { status = .idle; lastError = nil }
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Server has a newer version. LWW: pull and reconcile, then
            // re-push if our local is still newer.
            await pull()
            await pushAgainIfNeeded(record: record)
        } catch {
            NSLog("PurpleLife: push(\(record.id)) failed — \(error.localizedDescription)")
            status = .error(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    func pushDelete(recordId: String) async {
        guard isEnabled, let database else { return }
        do {
            let id = CKRecord.ID(recordName: recordId, zoneID: zoneID)
            _ = try await database.deleteRecord(withID: id)
            lastSyncAt = Date()
            if status.isError { status = .idle; lastError = nil }
        } catch let error as CKError where error.code == .unknownItem {
            // Already gone server-side; nothing to do.
        } catch {
            NSLog("PurpleLife: pushDelete(\(recordId)) failed — \(error.localizedDescription)")
            status = .error(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    // MARK: - Schema push (PurpleType)

    /// Mirror a local schema mutation (`SchemaRegistry.upsertType`)
    /// to CloudKit. Mirror of `push(record:)`. Errors are logged
    /// but don't surface — the local schema write already succeeded.
    func pushType(_ type: ObjectType) async {
        guard isEnabled, let database else { return }
        do {
            let ck = try await fetchOrMakeType(typeId: type.id)
            applyLocal(type: type, to: ck)
            _ = try await database.save(ck)
            lastSyncAt = Date()
            if status.isError { status = .idle; lastError = nil }
        } catch let error as CKError where error.code == .serverRecordChanged {
            // Server has a newer version — pull and reconcile.
            await pull()
        } catch {
            NSLog("PurpleLife: pushType(\(type.id)) failed — \(error.localizedDescription)")
            status = .error(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    func pushDeleteType(id: String) async {
        guard isEnabled, let database else { return }
        do {
            let ckID = CKRecord.ID(recordName: id, zoneID: zoneID)
            _ = try await database.deleteRecord(withID: ckID)
            lastSyncAt = Date()
            if status.isError { status = .idle; lastError = nil }
        } catch let error as CKError where error.code == .unknownItem {
            // Already gone server-side; nothing to do.
        } catch {
            NSLog("PurpleLife: pushDeleteType(\(id)) failed — \(error.localizedDescription)")
            status = .error(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    private func fetchOrMakeType(typeId: String) async throws -> CKRecord {
        guard let database else { throw CKError(.internalError) }
        let id = CKRecord.ID(recordName: typeId, zoneID: zoneID)
        do {
            return try await database.record(for: id)
        } catch let error as CKError where error.code == .unknownItem {
            return CKRecord(recordType: Self.typeRecordType, recordID: id)
        }
    }

    private func applyLocal(type: ObjectType, to ck: CKRecord) {
        // Plaintext updated_at for server-side LWW comparison; full
        // serialized type goes through encryptedValues so the schema's
        // field names + options aren't visible to Apple. Same shape
        // as the object record path.
        ck["updated_at"] = (type.updatedAt ?? ObjectType.epochTimestamp) as CKRecordValue
        if let data = try? JSONEncoder().encode(type) {
            ck.encryptedValues["typeJSON"] = data as CKRecordValue
        }
    }

    private func pushAgainIfNeeded(record: ObjectRecord) async {
        // After a serverRecordChanged retry, look up the local record
        // again — `pull` may have replaced it. If the local is still
        // fresher than what we just pulled, push.
        do {
            guard let current = try DatabaseService.shared.fetchObject(id: record.id) else { return }
            if current.updatedAt > record.updatedAt {
                // Local was updated again while we were retrying — push the latest.
                await push(record: current)
            } else if record.updatedAt > current.updatedAt {
                // Our caller's snapshot is newer than what's now in the DB;
                // means pull overwrote with an older remote (shouldn't happen
                // with LWW, but defensive).
                await push(record: record)
            }
            // else: in sync, nothing to do.
        } catch {
            NSLog("PurpleLife: pushAgainIfNeeded fetch failed — \(error.localizedDescription)")
        }
    }

    private func fetchOrMake(record: ObjectRecord) async throws -> CKRecord {
        guard let database else { throw CKError(.internalError) }
        let id = CKRecord.ID(recordName: record.id, zoneID: zoneID)
        do {
            return try await database.record(for: id)
        } catch let error as CKError where error.code == .unknownItem {
            return CKRecord(recordType: Self.recordType, recordID: id)
        }
    }

    private func applyLocal(record: ObjectRecord, to ck: CKRecord) {
        ck["type_id"]    = record.typeId    as CKRecordValue
        ck["parent_id"]  = (record.parentId ?? "") as CKRecordValue
        ck["created_at"] = record.createdAt as CKRecordValue
        ck["updated_at"] = record.updatedAt as CKRecordValue
        if let data = record.fieldsJSON.data(using: .utf8) {
            ck.encryptedValues["fieldsJSON"] = data as CKRecordValue
        }
    }

    /// On bootstrap, push any local rows that aren't yet in CloudKit.
    /// Cheap because `record(for:)` returns `unknownItem` quickly when a
    /// record doesn't exist — we don't have to maintain a separate
    /// "needs-push" queue for the starter.
    private func pushPendingLocalChanges() async {
        guard let database else { return }
        // Schemas first — a record arriving on the peer should find
        // its type definition already there, otherwise the FTS reindex
        // and `applyRemote` (which looks up the type to build
        // searchable text) skip the search-index update.
        await pushPendingLocalSchemas()
        do {
            let local = try DatabaseService.shared.fetchAllObjects()
            for r in local {
                let id = CKRecord.ID(recordName: r.id, zoneID: zoneID)
                let ck: CKRecord?
                do {
                    ck = try await database.record(for: id)
                } catch let error as CKError where error.code == .unknownItem {
                    ck = nil
                }
                let remoteUpdated = ck?["updated_at"] as? String ?? ""
                if remoteUpdated < r.updatedAt {
                    await push(record: r)
                }
            }
        } catch {
            NSLog("PurpleLife: pushPendingLocalChanges failed — \(error.localizedDescription)")
        }
    }

    /// Mirror of `pushPendingLocalChanges` for the schema. On
    /// bootstrap, push any local types whose `updatedAt` is ahead of
    /// (or absent from) the server. Newly-seeded built-ins carry the
    /// epoch timestamp, so a fresh-install peer doesn't push its
    /// untouched built-ins over a peer that's already customized
    /// them.
    private func pushPendingLocalSchemas() async {
        guard let database, let schema else { return }
        for type in schema.types {
            let id = CKRecord.ID(recordName: type.id, zoneID: zoneID)
            let ck: CKRecord?
            do {
                ck = try await database.record(for: id)
            } catch let error as CKError where error.code == .unknownItem {
                ck = nil
            } catch {
                NSLog("PurpleLife: pushPendingLocalSchemas fetch \(type.id) failed — \(error.localizedDescription)")
                continue
            }
            let remoteUpdated = ck?["updated_at"] as? String ?? ""
            let localUpdated = type.updatedAt ?? ObjectType.epochTimestamp
            if remoteUpdated < localUpdated {
                await pushType(type)
            }
        }
    }

    // MARK: - Pull

    private func pullInitial() async {
        // First-time sync uses no token (full fetch); subsequent calls
        // use the saved token. This is just a `pull()` with whatever
        // token we have saved.
        await pull()
    }

    func pull() async {
        guard isEnabled, !inFlight else { return }
        inFlight = true
        let prevStatus = status
        status = .syncing
        defer {
            inFlight = false
            if status == .syncing { status = .idle }
            // Preserve a sticky-error state if the pull failed.
            if case .error = prevStatus, status == .idle {
                lastError = nil
            }
        }

        do {
            try await runFetchOperation()
            lastSyncAt = Date()
        } catch let error as CKError where error.code == .changeTokenExpired {
            serverChangeToken = nil
            try? await runFetchOperation()
            lastSyncAt = Date()
        } catch {
            NSLog("PurpleLife: pull failed — \(error.localizedDescription)")
            status = .error(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    private func runFetchOperation() async throws {
        guard let database else { throw CKError(.internalError) }
        let cfg = CKFetchRecordZoneChangesOperation.ZoneConfiguration()
        cfg.previousServerChangeToken = serverChangeToken
        let op = CKFetchRecordZoneChangesOperation(
            recordZoneIDs: [zoneID],
            configurationsByRecordZoneID: [zoneID: cfg]
        )

        var changedRecords: [CKRecord] = []
        var deletedRecordIDs: [CKRecord.ID] = []

        op.recordWasChangedBlock = { _, result in
            switch result {
            case .success(let record): changedRecords.append(record)
            case .failure(let err):    NSLog("PurpleLife: change parse failed — \(err.localizedDescription)")
            }
        }
        op.recordWithIDWasDeletedBlock = { id, _ in
            deletedRecordIDs.append(id)
        }
        var newToken: CKServerChangeToken?
        op.recordZoneChangeTokensUpdatedBlock = { _, token, _ in
            newToken = token
        }
        op.recordZoneFetchResultBlock = { _, result in
            if case .success(let bundle) = result {
                newToken = bundle.serverChangeToken
            }
        }

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            op.fetchRecordZoneChangesResultBlock = { result in
                switch result {
                case .success: continuation.resume()
                case .failure(let err): continuation.resume(throwing: err)
                }
            }
            database.add(op)
        }

        // Apply schema changes BEFORE object changes — an arriving
        // object record needs its type already present so the FTS
        // search-index update in `applyRemote` can resolve fields.
        // Same logic in reverse for deletions: schema deletions go
        // last so any object records still living on the local DB
        // when the schema disappears don't lose their type lookup
        // mid-apply. CKFetchRecordZoneChangesOperation doesn't
        // guarantee record-type ordering inside a single fetch, so
        // we partition the buffered results and order them here.
        let typeChanges   = changedRecords.filter { $0.recordType == Self.typeRecordType }
        let objectChanges = changedRecords.filter { $0.recordType == Self.recordType }
        let objectDeletes = deletedRecordIDs.filter { id in
            // A deletion only tells us the record name + zone id, not
            // the type. Object record-ids match a UUID format that
            // is the same shape as type ids (UUID strings), so we
            // can't distinguish by name alone. Use a heuristic: if
            // the id matches a known local type, it's a type
            // deletion; otherwise treat as object. This is safe
            // because both apply* paths are idempotent — deleting a
            // missing local row is a no-op.
            schema?.type(id: id.recordName) == nil
        }
        let typeDeletes = deletedRecordIDs.filter { id in
            schema?.type(id: id.recordName) != nil
        }

        for record in typeChanges {
            await applyRemoteType(record)
        }
        for record in objectChanges {
            await applyRemote(record)
        }
        for id in objectDeletes {
            try? DatabaseService.shared.deleteObject(id: id.recordName)
            SearchService.delete(recordId: id.recordName)
        }
        for id in typeDeletes {
            schema?.applyRemoteDelete(typeId: id.recordName)
        }
        if let token = newToken {
            serverChangeToken = token
        }
    }

    /// LWW: apply a remote `PurpleType` record only if its
    /// `updated_at` beats the local. Same shape as `applyRemote`
    /// for object records.
    private func applyRemoteType(_ ck: CKRecord) async {
        guard let updatedAt = ck["updated_at"] as? String,
              let typeData  = ck.encryptedValues["typeJSON"] as? Data
        else {
            NSLog("PurpleLife: applyRemoteType skipped — malformed type \(ck.recordID.recordName)")
            return
        }
        var type: ObjectType
        do {
            type = try JSONDecoder().decode(ObjectType.self, from: typeData)
        } catch {
            NSLog("PurpleLife: applyRemoteType decode failed — \(error.localizedDescription)")
            return
        }
        // Ensure the timestamp the server stored wins — the encoded
        // JSON may carry an older one if a write race happened on the
        // remote side.
        type.updatedAt = updatedAt
        schema?.applyRemote(type)
    }

    /// LWW: apply the remote record only if its `updated_at` is greater
    /// than our local. This is the same-field-edit reconciliation path
    /// from the Phase 4 acceptance gate.
    private func applyRemote(_ ck: CKRecord) async {
        guard let typeId    = ck["type_id"]    as? String,
              let createdAt = ck["created_at"] as? String,
              let updatedAt = ck["updated_at"] as? String,
              let fieldsData = ck.encryptedValues["fieldsJSON"] as? Data,
              let fieldsJSON = String(data: fieldsData, encoding: .utf8)
        else {
            NSLog("PurpleLife: applyRemote skipped — malformed record \(ck.recordID.recordName)")
            return
        }
        let parentId = (ck["parent_id"] as? String).flatMap { $0.isEmpty ? nil : $0 }

        let local = try? DatabaseService.shared.fetchObject(id: ck.recordID.recordName)
        if let local, local.updatedAt >= updatedAt {
            // Local is at least as fresh — keep it. Push will eventually
            // overwrite the remote (by either our normal push hook or a
            // future pushPendingLocalChanges).
            return
        }

        let record = ObjectRecord(
            id: ck.recordID.recordName,
            typeId: typeId,
            parentId: parentId,
            fieldsJSON: fieldsJSON,
            createdAt: createdAt,
            updatedAt: updatedAt
        )
        do {
            try DatabaseService.shared.upsertObject(record)
            if let schema, let type = schema.type(id: typeId) {
                SearchService.upsert(record: record, type: type)
            }
        } catch {
            NSLog("PurpleLife: applyRemote upsert failed — \(error.localizedDescription)")
        }
    }

    // MARK: - State helpers

    private var isEnabled: Bool {
        switch status {
        case .disabled, .notSignedIn: return false
        default:                      return true
        }
    }
}
