import Foundation
import MasterClipperCore

enum IntentOutboxError: LocalizedError {
    case noUbiquityContainer
    case noManifest
    case writeFailed(String)

    var errorDescription: String? {
        switch self {
        case .noUbiquityContainer:
            return "iCloud Drive is not available. Sign in to iCloud in Settings."
        case .noManifest:
            return "No snapshot loaded yet — pull to refresh, or wait for iCloud."
        case .writeFailed(let msg):
            return "Couldn't write the change to iCloud: \(msg)"
        }
    }
}

/// Composes `IntentEnvelope`s and writes them as JSON files into
/// `iCloud/Documents/intents/pending/`. The Mac's `IntentInbox` picks them
/// up via `NSMetadataQuery` and applies them to the live SQLite database.
@MainActor
final class IntentOutbox: ObservableObject {

    /// UUIDs of intents we've written that the Mac hasn't yet acknowledged via
    /// a new snapshot (`manifest.generated_at > intent.createdAt`). Persisted
    /// to `pendingIntents.json` in the app sandbox so a relaunch doesn't lose
    /// the pending state.
    @Published private(set) var pendingByClipId: [String: [PendingIntentRef]] = [:]

    @Published private(set) var lastError: String?

    private let reader: SnapshotReader
    private let pendingStoreURL: URL

    init(reader: SnapshotReader) {
        self.reader = reader
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        self.pendingStoreURL = docs.appendingPathComponent("pendingIntents.json")
        loadPendingState()
    }

    // MARK: - Public submission API

    func submitMarkPosted(clipId: String, siteCode: String, postedDate: Date = Date()) async -> Bool {
        await submit(
            clipId: clipId,
            kind: .markPosted,
            payload: .markPosted(siteCode: siteCode, postedDate: Self.isoDate(postedDate)),
            description: "Mark posted on \(siteCode)"
        )
    }

    func submitUnmarkPosted(clipId: String, siteCode: String) async -> Bool {
        await submit(
            clipId: clipId,
            kind: .unmarkPosted,
            payload: .unmarkPosted(siteCode: siteCode),
            description: "Unmark posted on \(siteCode)"
        )
    }

    func submitAddNote(clipId: String, body: String, operatorName: String) async -> Bool {
        await submit(
            clipId: clipId,
            kind: .addNote,
            payload: .addNote(body: body, operatorName: operatorName),
            description: "Add note"
        )
    }

    func submitSetStatus(clipId: String, status: String?) async -> Bool {
        await submit(
            clipId: clipId,
            kind: .setStatus,
            payload: .setStatus(status: status),
            description: status == nil ? "Clear status override" : "Set status to \(status!)"
        )
    }

    func submitTogglePostingExcluded(clipId: String, excluded: Bool, reason: String, notes: String) async -> Bool {
        await submit(
            clipId: clipId,
            kind: .togglePostingExcluded,
            payload: .togglePostingExcluded(excluded: excluded, reason: reason, notes: notes),
            description: excluded ? "Exclude from posting" : "Include in posting"
        )
    }

    // MARK: - Pending tracking

    func hasPending(forClip clipId: String) -> Bool {
        !(pendingByClipId[clipId]?.isEmpty ?? true)
    }

    func pendingDescriptions(forClip clipId: String) -> [String] {
        (pendingByClipId[clipId] ?? []).map(\.description)
    }

    /// Called after every snapshot reload — drop any pending entries whose
    /// `createdAt` is older than the new manifest. That manifest is the
    /// Mac's confirmation it has applied them.
    func reconcileWithManifest(_ manifest: SnapshotManifest) {
        let isoIn = ISO8601DateFormatter()
        isoIn.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        guard let manifestDate = isoIn.date(from: manifest.generatedAt) else { return }

        var changed = false
        for (clipId, refs) in pendingByClipId {
            let kept = refs.filter { $0.createdAt > manifestDate }
            if kept.count != refs.count { changed = true }
            if kept.isEmpty {
                pendingByClipId.removeValue(forKey: clipId)
            } else {
                pendingByClipId[clipId] = kept
            }
        }
        if changed { savePendingState() }
    }

    // MARK: - Submit

    private func submit(
        clipId: String,
        kind: IntentKind,
        payload: IntentPayload,
        description: String
    ) async -> Bool {
        do {
            guard let container = FileManager.default.url(
                forUbiquityContainerIdentifier: SnapshotLayout.iCloudContainerID) else {
                throw IntentOutboxError.noUbiquityContainer
            }
            guard let manifest = reader.manifest else {
                throw IntentOutboxError.noManifest
            }

            let envelope = IntentEnvelope(
                kind: kind,
                clipId: clipId,
                payload: payload,
                deviceId: Self.deviceId(),
                baseSnapshotGeneratedAt: manifest.generatedAt,
                appVersion: Self.appVersion()
            )

            // Encode.
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(envelope)

            // Write into pending/<uuid>.json under NSFileCoordinator.
            let pendingDir = IntentLayout.pendingDirURL(in: container)
            try FileManager.default.createDirectory(at: pendingDir, withIntermediateDirectories: true)
            let dest = pendingDir.appendingPathComponent("\(envelope.id.uuidString).json")

            try await writeCoordinated(data: data, to: dest)

            // Track locally.
            let ref = PendingIntentRef(
                id: envelope.id,
                kind: kind,
                createdAt: envelope.createdAt,
                description: description
            )
            pendingByClipId[clipId, default: []].append(ref)
            savePendingState()
            lastError = nil
            return true
        } catch {
            lastError = error.localizedDescription
            return false
        }
    }

    private func writeCoordinated(data: Data, to url: URL) async throws {
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            let coordinator = NSFileCoordinator(filePresenter: nil)
            var coordError: NSError?
            var writeError: Error?
            coordinator.coordinate(writingItemAt: url,
                                   options: .forReplacing,
                                   error: &coordError) { writeURL in
                do {
                    try data.write(to: writeURL, options: .atomic)
                } catch {
                    writeError = error
                }
            }
            if let err = coordError {
                cont.resume(throwing: err)
            } else if let err = writeError {
                cont.resume(throwing: err)
            } else {
                cont.resume(returning: ())
            }
        }
    }

    // MARK: - Pending persistence

    private func loadPendingState() {
        guard let data = try? Data(contentsOf: pendingStoreURL) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let decoded = try? decoder.decode([String: [PendingIntentRef]].self, from: data) {
            pendingByClipId = decoded
        }
    }

    private func savePendingState() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        if let data = try? encoder.encode(pendingByClipId) {
            try? data.write(to: pendingStoreURL, options: .atomic)
        }
    }

    // MARK: - Helpers

    private static func deviceId() -> String {
        let key = "MasterClipperiOS.deviceId"
        if let existing = UserDefaults.standard.string(forKey: key) { return existing }
        let id = "ios-\(UUID().uuidString.prefix(8))"
        UserDefaults.standard.set(id, forKey: key)
        return String(id)
    }

    private static func appVersion() -> String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        return "\(v) (\(b))"
    }

    private static func isoDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd"
        fmt.locale = Locale(identifier: "en_US_POSIX")
        return fmt.string(from: date)
    }
}

struct PendingIntentRef: Codable, Identifiable, Hashable {
    let id: UUID
    let kind: IntentKind
    let createdAt: Date
    let description: String
}
