import Foundation
import CloudKit
import GRDB
import MasterClipperCore

enum ShareManagerError: LocalizedError {
    case noClipsSelected
    case clipNotFound(String)
    case ckError(String)
    case shareAlreadyExists

    var errorDescription: String? {
        switch self {
        case .noClipsSelected:        return "Pick at least one clip to share."
        case .clipNotFound(let id):   return "Clip \(id) was not found in the local database."
        case .ckError(let msg):       return "CloudKit error: \(msg)"
        case .shareAlreadyExists:     return "A share with this ID already exists."
        }
    }
}

/// Lightweight summary of an active share — what the macOS UI binds against.
struct ShareSummary: Identifiable, Hashable {
    let id: UUID
    let label: String?
    let permission: SharePermission
    let clipCount: Int
    let expiresAt: Date
    let createdAt: Date
    let revoked: Bool
    let participationURL: URL?

    var isExpired: Bool { Date() >= expiresAt }

    var timeRemainingDescription: String {
        if revoked { return "Revoked" }
        if isExpired { return "Expired" }
        let interval = expiresAt.timeIntervalSinceNow
        let hours = Int(interval / 3600)
        let days = hours / 24
        if days >= 2 { return "\(days)d left" }
        if hours >= 2 { return "\(hours)h left" }
        let minutes = max(1, Int(interval / 60))
        return "\(minutes)m left"
    }
}

@MainActor
final class ShareManager: ObservableObject {
    static let shared = ShareManager()

    @Published private(set) var activeShares: [ShareSummary] = []
    @Published private(set) var lastError: String?
    @Published private(set) var isBusy: Bool = false

    private let container: CKContainer
    private var privateDB: CKDatabase { container.privateCloudDatabase }

    private init() {
        self.container = CKContainer(identifier: SnapshotLayout.iCloudContainerID)
    }

    // MARK: - Public API

    /// Create a new share. Uploads `SharedClip` records into a freshly-created
    /// zone, creates a `CKShare` with the chosen permission, and returns the
    /// participation URL the user can text/email to their recipient.
    func createShare(
        clipIds: [String],
        permission: SharePermission,
        expiresAt: Date,
        label: String?
    ) async throws -> URL {
        guard !clipIds.isEmpty else { throw ShareManagerError.noClipsSelected }
        isBusy = true
        defer { isBusy = false }

        let shareId = UUID()
        let zoneName = CKShareSchema.zoneName(forShareId: shareId)
        let zoneID = CKRecordZone.ID(zoneName: zoneName, ownerName: CKCurrentUserDefaultName)

        // 1. Create the zone in our private database.
        let zone = CKRecordZone(zoneID: zoneID)
        try await save(zone)

        // 2. Build SharedClip + ShareMetadata records and a CKShare. We save
        //    them together so the share lifecycle is atomic per zone.
        let metadataRecord = makeMetadataRecord(
            shareId: shareId,
            label: label,
            permission: permission,
            expiresAt: expiresAt,
            zoneID: zoneID
        )
        let clipRecords = try makeSharedClipRecords(
            clipIds: clipIds,
            expiresAt: expiresAt,
            zoneID: zoneID
        )

        // CKShare anchors on a root record. We use the metadata record as the
        // root — any operation on the share will route the recipient through
        // the metadata record first.
        let share = CKShare(rootRecord: metadataRecord)
        share[CKShare.SystemFieldKey.title] = (label ?? "MasterClipper share") as CKRecordValue
        share.publicPermission = .none
        share[CKShare.SystemFieldKey.shareType] = "com.bronty13.MasterClipper.share" as CKRecordValue

        let recordsToSave: [CKRecord] = [metadataRecord, share] + clipRecords
        try await saveAll(recordsToSave)

        guard let url = share.url else {
            throw ShareManagerError.ckError("CloudKit did not produce a participation URL.")
        }

        await refreshActiveShares()
        return url
    }

    /// Replace the SharedClip record for a given clip in a given share. Used
    /// when the live macOS clip changes so recipients see the update.
    func pushUpdate(clipId: String, intoShareId shareId: UUID) async {
        let zoneID = CKRecordZone.ID(zoneName: CKShareSchema.zoneName(forShareId: shareId),
                                     ownerName: CKCurrentUserDefaultName)
        do {
            // Re-derive the record from the current live clip.
            guard let metadata = try await fetchShareMetadata(zoneID: zoneID) else { return }
            let records = try makeSharedClipRecords(
                clipIds: [clipId],
                expiresAt: metadata.expiresAt,
                zoneID: zoneID
            )
            try await saveAll(records)
        } catch {
            lastError = "pushUpdate(\(clipId)) failed: \(error.localizedDescription)"
        }
    }

    /// Tear down a share entirely — deletes the zone, which removes the
    /// CKShare, all SharedClip records, and the metadata. Recipients get a
    /// "no longer available" state on next CK fetch.
    func revokeShare(_ shareId: UUID) async {
        let zoneID = CKRecordZone.ID(zoneName: CKShareSchema.zoneName(forShareId: shareId),
                                     ownerName: CKCurrentUserDefaultName)
        isBusy = true
        defer { isBusy = false }
        do {
            try await privateDB.deleteRecordZone(withID: zoneID)
        } catch {
            lastError = "revokeShare failed: \(error.localizedDescription)"
        }
        await refreshActiveShares()
    }

    /// Load every share zone we own in the private database, decode the
    /// metadata + count clips, and publish to `activeShares`.
    func refreshActiveShares() async {
        do {
            let zones = try await privateDB.allRecordZones()
            var summaries: [ShareSummary] = []
            for zone in zones where zone.zoneID.zoneName.hasPrefix(CKShareSchema.zoneNamePrefix) {
                guard let metadata = try await fetchShareMetadata(zoneID: zone.zoneID) else { continue }
                let clipCount = try await countSharedClips(zoneID: zone.zoneID)
                let url = try await fetchShareURL(zoneID: zone.zoneID)
                summaries.append(ShareSummary(
                    id: metadata.id,
                    label: metadata.label,
                    permission: metadata.permission,
                    clipCount: clipCount,
                    expiresAt: metadata.expiresAt,
                    createdAt: metadata.createdAt,
                    revoked: metadata.revoked,
                    participationURL: url
                ))
            }
            summaries.sort { $0.expiresAt < $1.expiresAt }
            self.activeShares = summaries
        } catch {
            lastError = "refreshActiveShares failed: \(error.localizedDescription)"
        }
    }

    /// Auto-revoke pass — call on app foreground + on a timer. Returns the
    /// number revoked.
    @discardableResult
    func revokeExpiredShares() async -> Int {
        var count = 0
        for share in activeShares where share.isExpired && !share.revoked {
            await revokeShare(share.id)
            count += 1
        }
        return count
    }

    // MARK: - Record building

    private func makeMetadataRecord(
        shareId: UUID,
        label: String?,
        permission: SharePermission,
        expiresAt: Date,
        zoneID: CKRecordZone.ID
    ) -> CKRecord {
        let recordID = CKRecord.ID(recordName: CKShareSchema.shareMetadataRecordName, zoneID: zoneID)
        let r = CKRecord(recordType: CKShareSchema.shareMetadataRecordType, recordID: recordID)
        r[CKShareSchema.ShareMetadataField.expiresAt]         = expiresAt as CKRecordValue
        r[CKShareSchema.ShareMetadataField.permission]        = permission.rawValue as CKRecordValue
        r[CKShareSchema.ShareMetadataField.label]             = label as CKRecordValue?
        r[CKShareSchema.ShareMetadataField.createdAt]         = Date() as CKRecordValue
        r[CKShareSchema.ShareMetadataField.revoked]           = 0 as CKRecordValue
        r[CKShareSchema.ShareMetadataField.createdByDeviceId] = Self.deviceId() as CKRecordValue
        return r
    }

    private func makeSharedClipRecords(
        clipIds: [String],
        expiresAt: Date,
        zoneID: CKRecordZone.ID
    ) throws -> [CKRecord] {
        let pool = DatabaseService.shared.dbPool
        return try pool.read { db -> [CKRecord] in
            var out: [CKRecord] = []
            for clipId in clipIds {
                guard let clip = try Clip.fetchOne(db, key: clipId) else {
                    throw ShareManagerError.clipNotFound(clipId)
                }
                let postings = try ClipPosting.filter(Column("clip_id") == clipId).fetchAll(db)
                let notes    = try ClipNote.filter(Column("clip_id") == clipId).fetchAll(db)

                let recordID = CKRecord.ID(recordName: clipId, zoneID: zoneID)
                let r = CKRecord(recordType: CKShareSchema.sharedClipRecordType, recordID: recordID)
                let F = CKShareSchema.SharedClipField.self

                r[F.clipId]             = clip.id as CKRecordValue
                r[F.title]              = clip.title as CKRecordValue
                r[F.descriptionRefined] = clip.descriptionRefined as CKRecordValue
                r[F.descriptionRaw]     = clip.descriptionRaw as CKRecordValue
                r[F.keywords]           = clip.keywords as CKRecordValue
                r[F.performers]         = clip.performers as CKRecordValue
                r[F.personaCode]        = clip.personaCode as CKRecordValue
                r[F.status]             = clip.status as CKRecordValue
                r[F.statusOverride]     = clip.statusOverride as CKRecordValue?
                r[F.archived]           = (clip.archived ? 1 : 0) as CKRecordValue
                r[F.postingExcluded]    = (clip.postingExcluded ? 1 : 0) as CKRecordValue
                r[F.exclusionReason]    = clip.exclusionReason as CKRecordValue
                r[F.exclusionNotes]     = clip.exclusionNotes as CKRecordValue
                r[F.goLiveDate]         = clip.goLiveDate as CKRecordValue?
                r[F.contentDate]        = clip.contentDate as CKRecordValue?
                r[F.lengthSeconds]      = clip.lengthSeconds as CKRecordValue?
                r[F.priceCents]         = clip.priceCents as CKRecordValue?
                r[F.salesCount]         = clip.salesCount as CKRecordValue
                r[F.incomeCents]        = clip.incomeCents as CKRecordValue
                r[F.expiresAt]          = expiresAt as CKRecordValue

                let encoder = JSONEncoder()
                if let p = try? encoder.encode(postings) {
                    r[F.postingsJson] = String(data: p, encoding: .utf8) as CKRecordValue?
                }
                if let n = try? encoder.encode(notes) {
                    r[F.notesJson] = String(data: n, encoding: .utf8) as CKRecordValue?
                }

                // Thumbnail attachment — read from the existing iCloud snapshot
                // thumbnails folder so we don't pay the cost twice.
                if let thumbURL = Self.thumbnailURL(forClipId: clipId),
                   FileManager.default.fileExists(atPath: thumbURL.path) {
                    r[F.thumbnail] = CKAsset(fileURL: thumbURL)
                }

                out.append(r)
            }
            return out
        }
    }

    // MARK: - CK reads

    private func fetchShareMetadata(zoneID: CKRecordZone.ID) async throws -> ShareMetadata? {
        let recordID = CKRecord.ID(recordName: CKShareSchema.shareMetadataRecordName, zoneID: zoneID)
        do {
            let record = try await privateDB.record(for: recordID)
            return Self.decodeMetadata(record)
        } catch let error as CKError where error.code == .unknownItem {
            return nil
        }
    }

    private func fetchShareURL(zoneID: CKRecordZone.ID) async throws -> URL? {
        // The CKShare for this zone is at the metadata record's share reference.
        let metadataID = CKRecord.ID(recordName: CKShareSchema.shareMetadataRecordName, zoneID: zoneID)
        guard let metadataRecord = try? await privateDB.record(for: metadataID) else { return nil }
        guard let shareRef = metadataRecord.share else { return nil }
        let shareRecord = try await privateDB.record(for: shareRef.recordID)
        return (shareRecord as? CKShare)?.url
    }

    private func countSharedClips(zoneID: CKRecordZone.ID) async throws -> Int {
        let query = CKQuery(
            recordType: CKShareSchema.sharedClipRecordType,
            predicate: NSPredicate(value: true)
        )
        let result = try await privateDB.records(matching: query, inZoneWith: zoneID)
        return result.matchResults.count
    }

    // MARK: - CK write helpers

    private func save(_ zone: CKRecordZone) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let op = CKModifyRecordZonesOperation(recordZonesToSave: [zone], recordZoneIDsToDelete: nil)
            op.modifyRecordZonesResultBlock = { result in
                switch result {
                case .success:        cont.resume()
                case .failure(let e): cont.resume(throwing: e)
                }
            }
            privateDB.add(op)
        }
    }

    private func saveAll(_ records: [CKRecord]) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let op = CKModifyRecordsOperation(recordsToSave: records, recordIDsToDelete: nil)
            op.savePolicy = .changedKeys
            op.modifyRecordsResultBlock = { result in
                switch result {
                case .success:        cont.resume()
                case .failure(let e): cont.resume(throwing: e)
                }
            }
            privateDB.add(op)
        }
    }

    // MARK: - Helpers

    private static func decodeMetadata(_ record: CKRecord) -> ShareMetadata? {
        let F = CKShareSchema.ShareMetadataField.self
        guard
            let expiresAt   = record[F.expiresAt] as? Date,
            let permission  = (record[F.permission] as? String).flatMap(SharePermission.init(rawValue:)),
            let createdAt   = record[F.createdAt] as? Date
        else { return nil }
        let label    = record[F.label] as? String
        let device   = (record[F.createdByDeviceId] as? String) ?? ""
        let revoked  = ((record[F.revoked] as? Int) ?? 0) == 1
        guard let id = CKShareSchema.shareId(fromZoneName: record.recordID.zoneID.zoneName) else { return nil }
        return ShareMetadata(
            id: id, label: label, permission: permission,
            expiresAt: expiresAt, createdAt: createdAt,
            createdByDeviceId: device, revoked: revoked
        )
    }

    private static func thumbnailURL(forClipId clipId: String) -> URL? {
        FileManager.default
            .url(forUbiquityContainerIdentifier: SnapshotLayout.iCloudContainerID)?
            .appendingPathComponent("Documents", isDirectory: true)
            .appendingPathComponent(SnapshotLayout.snapshotDir, isDirectory: true)
            .appendingPathComponent(SnapshotLayout.thumbnailsDir, isDirectory: true)
            .appendingPathComponent("\(clipId).jpg")
    }

    private static func deviceId() -> String {
        let key = "MasterClipper.publisherDeviceId"
        return UserDefaults.standard.string(forKey: key) ?? "mac"
    }
}
