import Foundation
import CloudKit
import MasterClipperCore

enum SharedZoneReaderError: LocalizedError {
    case acceptFailed(String)
    case ckError(String)

    var errorDescription: String? {
        switch self {
        case .acceptFailed(let msg): return "Couldn't accept the share: \(msg)"
        case .ckError(let msg):      return "CloudKit error: \(msg)"
        }
    }
}

/// Manages CKShare acceptance + reads from `CKContainer.sharedCloudDatabase`.
/// Exposes `sessions`, one per accepted share. Each session carries the
/// ShareMetadata (permission, expiry) and the list of SharedClipRow records.
@MainActor
final class SharedZoneReader: ObservableObject {

    @Published private(set) var sessions: [SharedShareSession] = []
    @Published private(set) var isWorking: Bool = false
    @Published private(set) var lastError: String?

    /// Map of share UUID → the actual CK zoneID enumerated from
    /// `sharedCloudDatabase`. The zoneID's ownerName is the share owner's
    /// CKUserRecordID name, which the recipient can't construct from
    /// scratch — only fetched. SharedZoneEditor uses this to address the
    /// right zone when writing edits.
    private(set) var zoneIDByShare: [UUID: CKRecordZone.ID] = [:]

    private let container: CKContainer
    private var sharedDB: CKDatabase { container.sharedCloudDatabase }

    init() {
        self.container = CKContainer(identifier: SnapshotLayout.iCloudContainerID)
    }

    // MARK: - Accept

    /// Accept a share metadata handed to us by iOS (via SceneDelegate's
    /// `userDidAcceptCloudKitShareWith` or .onContinueUserActivity).
    func accept(_ metadata: CKShare.Metadata) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await acceptInternal(metadata)
            await refresh()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func acceptInternal(_ metadata: CKShare.Metadata) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let op = CKAcceptSharesOperation(shareMetadatas: [metadata])
            op.perShareResultBlock = { _, result in
                if case .failure(let err) = result {
                    cont.resume(throwing: err)
                }
            }
            op.acceptSharesResultBlock = { result in
                switch result {
                case .success:        cont.resume()
                case .failure(let e): cont.resume(throwing: e)
                }
            }
            container.add(op)
        }
    }

    // MARK: - Refresh

    /// Re-pull every shared zone we've accepted, decode records, refresh
    /// `sessions`. Call on app launch + after accepting a new share.
    func refresh() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let zones = try await sharedDB.allRecordZones()
            var built: [SharedShareSession] = []
            var zoneMap: [UUID: CKRecordZone.ID] = [:]
            for zone in zones where zone.zoneID.zoneName.hasPrefix(CKShareSchema.zoneNamePrefix) {
                if let session = try await loadSession(zoneID: zone.zoneID) {
                    built.append(session)
                    zoneMap[session.id] = zone.zoneID
                }
            }
            // Strip expired sessions client-side as belt-and-suspenders;
            // ShareExpiryScheduler on the Mac should already have revoked.
            built = built.filter { !$0.isExpired }
            built.sort { $0.metadata.expiresAt < $1.metadata.expiresAt }
            self.sessions = built
            self.zoneIDByShare = zoneMap
            self.lastError = nil
        } catch {
            self.lastError = "refresh failed: \(error.localizedDescription)"
        }
    }

    private func loadSession(zoneID: CKRecordZone.ID) async throws -> SharedShareSession? {
        guard let metadataRecord = try await fetchMetadataRecord(zoneID: zoneID),
              let metadata = decodeMetadata(metadataRecord)
        else { return nil }

        let clipRecords = try await fetchClipRecords(zoneID: zoneID)
        let clips: [SharedClipRow] = clipRecords.compactMap { decodeClip($0, expiresAt: metadata.expiresAt) }
        return SharedShareSession(id: metadata.id, metadata: metadata, clips: clips)
    }

    private func fetchMetadataRecord(zoneID: CKRecordZone.ID) async throws -> CKRecord? {
        let id = CKRecord.ID(recordName: CKShareSchema.shareMetadataRecordName, zoneID: zoneID)
        do {
            return try await sharedDB.record(for: id)
        } catch let e as CKError where e.code == .unknownItem {
            return nil
        }
    }

    private func fetchClipRecords(zoneID: CKRecordZone.ID) async throws -> [CKRecord] {
        let query = CKQuery(
            recordType: CKShareSchema.sharedClipRecordType,
            predicate: NSPredicate(value: true)
        )
        let result = try await sharedDB.records(matching: query, inZoneWith: zoneID)
        return result.matchResults.compactMap { _, recResult -> CKRecord? in
            if case .success(let r) = recResult { return r }
            return nil
        }
    }

    // MARK: - Decoding

    private func decodeMetadata(_ record: CKRecord) -> ShareMetadata? {
        let F = CKShareSchema.ShareMetadataField.self
        guard
            let expiresAt   = record[F.expiresAt] as? Date,
            let permission  = (record[F.permission] as? String).flatMap(SharePermission.init(rawValue:)),
            let createdAt   = record[F.createdAt] as? Date,
            let id          = CKShareSchema.shareId(fromZoneName: record.recordID.zoneID.zoneName)
        else { return nil }
        return ShareMetadata(
            id: id,
            label: record[F.label] as? String,
            permission: permission,
            expiresAt: expiresAt,
            createdAt: createdAt,
            createdByDeviceId: (record[F.createdByDeviceId] as? String) ?? "",
            revoked: ((record[F.revoked] as? Int) ?? 0) == 1
        )
    }

    private func decodeClip(_ record: CKRecord, expiresAt: Date) -> SharedClipRow? {
        let F = CKShareSchema.SharedClipField.self
        guard let clipId = record[F.clipId] as? String else { return nil }

        let decoder = JSONDecoder()
        let postings: [ClipPosting]
        if let json = record[F.postingsJson] as? String,
           let data = json.data(using: .utf8),
           let decoded = try? decoder.decode([ClipPosting].self, from: data) {
            postings = decoded
        } else {
            postings = []
        }
        let notes: [ClipNote]
        if let json = record[F.notesJson] as? String,
           let data = json.data(using: .utf8),
           let decoded = try? decoder.decode([ClipNote].self, from: data) {
            notes = decoded
        } else {
            notes = []
        }

        let thumbnailURL: URL? = (record[F.thumbnail] as? CKAsset)?.fileURL

        return SharedClipRow(
            id: clipId,
            title: (record[F.title] as? String) ?? "",
            descriptionRefined: (record[F.descriptionRefined] as? String) ?? "",
            descriptionRaw: (record[F.descriptionRaw] as? String) ?? "",
            keywords: (record[F.keywords] as? String) ?? "",
            performers: (record[F.performers] as? String) ?? "",
            personaCode: (record[F.personaCode] as? String) ?? "",
            status: (record[F.status] as? String) ?? "new",
            statusOverride: record[F.statusOverride] as? String,
            archived: ((record[F.archived] as? Int) ?? 0) == 1,
            postingExcluded: ((record[F.postingExcluded] as? Int) ?? 0) == 1,
            exclusionReason: (record[F.exclusionReason] as? String) ?? "",
            exclusionNotes: (record[F.exclusionNotes] as? String) ?? "",
            goLiveDate: record[F.goLiveDate] as? String,
            contentDate: record[F.contentDate] as? String,
            lengthSeconds: record[F.lengthSeconds] as? Int,
            priceCents: record[F.priceCents] as? Int,
            salesCount: (record[F.salesCount] as? Int) ?? 0,
            incomeCents: (record[F.incomeCents] as? Int) ?? 0,
            postings: postings,
            notes: notes,
            thumbnailLocalURL: thumbnailURL,
            expiresAt: expiresAt
        )
    }
}
