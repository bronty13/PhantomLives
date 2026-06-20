import Foundation

/// One audited purge *action* — a staging or a deletion that actually touched the Photos library.
/// Until now PurpleAttic kept **no record** of what it removed; this closes that gap so the
/// dashboard can answer "how many photos have been purged, and when". Every code path that adds to
/// the To-Delete album or calls `deleteAssets` appends one of these, whether triggered by the
/// nightly stage-agent (`trigger == .auto`) or a button in the GUI (`trigger == .manual`).
public struct PurgeAuditRecord: Codable, Sendable, Identifiable, Equatable {
    public enum Trigger: String, Codable, Sendable { case auto, manual }
    public enum Action: String, Codable, Sendable { case stage, delete }

    public var id: String           // ISO-ish timestamp + action, unique enough for a UI list
    public var timestamp: Date
    public var trigger: Trigger
    public var action: Action
    public var requested: Int       // uuids handed to the operation
    public var resolved: Int        // PHAssets actually matched in Photos
    public var succeeded: Int       // added (stage) or deleted (delete)
    public var failed: Int
    public var bytes: Int64         // best-effort freed/staged size (from the manifest)
    public var album: String?       // for stage actions
    public var note: String?

    public init(timestamp: Date, trigger: Trigger, action: Action, requested: Int, resolved: Int,
                succeeded: Int, failed: Int, bytes: Int64, album: String? = nil, note: String? = nil) {
        let stamp = PurgeAuditRecord.stampFormatter.string(from: timestamp)
        self.id = "\(stamp)-\(action.rawValue)"
        self.timestamp = timestamp
        self.trigger = trigger; self.action = action
        self.requested = requested; self.resolved = resolved
        self.succeeded = succeeded; self.failed = failed
        self.bytes = bytes; self.album = album; self.note = note
    }

    static let stampFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyyMMdd-HHmmss"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
}

/// Append-only audit log in `~/Library/Application Support/PurpleAttic/purge-audit.jsonl`.
public enum PurgeAuditStore {
    public static func defaultURL() -> URL {
        ProfileStore.defaultDirectory().appendingPathComponent("purge-audit.jsonl")
    }

    @discardableResult
    public static func append(_ record: PurgeAuditRecord, to url: URL = defaultURL()) -> Bool {
        AtticJSON.appendLine(record, to: url)
    }

    /// All records, oldest-first by timestamp.
    public static func load(from url: URL = defaultURL()) -> [PurgeAuditRecord] {
        AtticJSON.loadLines(PurgeAuditRecord.self, from: url).sorted { $0.timestamp < $1.timestamp }
    }
}
