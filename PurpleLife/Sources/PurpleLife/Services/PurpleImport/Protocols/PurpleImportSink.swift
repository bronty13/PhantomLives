import Foundation

/// What a target application must implement to receive records from
/// Purple Import. PurpleLife's concrete adapter is
/// `Sinks/PurpleLifeSink.swift`; a sibling PhantomLives app would
/// write its own conformer against its own record store.
///
/// String-keyed everything is deliberate — PurpleLife (and the other
/// PhantomLives data apps surveyed) already use stable string ids for
/// types and field keys, and associated-type protocols read poorly in
/// SwiftUI views. Type safety can be reintroduced inside the sink
/// implementation with strong wrappers around these ids.
@MainActor
protocol PurpleImportSink: AnyObject {

    // MARK: - Schema introspection

    /// Every type the sink can write to. Vault types are included so
    /// the wizard can let the user import into the Vault — the wizard
    /// gates on `AppState.vaultRevealed` for the surface UI; the
    /// sink itself is intentionally not session-aware.
    func listTypes() throws -> [SinkTypeInfo]

    /// The fields on one type, in the order the user sees them.
    func listFields(typeId: String) throws -> [SinkFieldInfo]

    // MARK: - Schema mutation (inline edit during mapping)

    /// Create a new type matching `proposal`. Returns the assigned
    /// type id. The sink is free to munge `name` for uniqueness
    /// (e.g. append "(imported)") — the wizard surfaces the final
    /// id back to the user.
    func createType(_ proposal: SinkTypeProposal) throws -> String

    /// Append a new field to an existing type. Returns the assigned
    /// field key (the sink may slug-ify the user's name to make it
    /// safe for storage).
    func addField(typeId: String, _ proposal: SinkFieldProposal) throws -> String

    // MARK: - Record writes

    /// Per-record write — used for previews and small imports
    /// (≤ `PurpleImport.bulkThreshold` rows). The implementor is
    /// expected to make this idempotent on `keyFieldKey` if the
    /// mapping's upsert strategy is `.upsertOnKey`; the runner
    /// passes `nil` for insert-only.
    func upsert(
        typeId: String,
        keyFieldKey: String?,
        values: [String: Any],
        attachments: [SinkAttachment]
    ) throws -> SinkUpsertResult

    /// Bulk path — used for imports > `PurpleImport.bulkThreshold`
    /// rows. The implementor is contractually obliged to:
    ///   1. Register a single coalesced undo entry covering the whole
    ///      batch (so the user can ⌘Z the import in one go).
    ///   2. Defer per-record CloudKit push; emit one signal at the
    ///      end of the run.
    ///   3. Update the search index once per record inside one DB
    ///      transaction (or via a single end-of-run reindex if the
    ///      sink prefers).
    /// Returns a struct rather than an `AsyncStream` for Phase 1 —
    /// streaming progress is wired in by the runner one layer up
    /// using a callback on each row.
    func bulkInsert(
        typeId: String,
        rows: [[String: Any]]
    ) throws -> SinkBulkInsertResult
}

// MARK: - Value types

struct SinkTypeInfo: Hashable {
    let id: String
    let name: String
    let pluralName: String
    let systemImage: String
    let isVault: Bool
}

struct SinkFieldInfo: Hashable {
    let key: String
    let name: String
    let kind: FieldKind
    let options: [FieldOption]
    let required: Bool
}

/// Inputs the wizard collects when the user chooses "Create new
/// type from this source" at the target-pick step.
struct SinkTypeProposal {
    let name: String
    let pluralName: String
    let systemImage: String
    let colorHex: String
    let fields: [SinkFieldProposal]
    let isVault: Bool
}

struct SinkFieldProposal {
    let name: String
    let kind: FieldKind
    let options: [FieldOption]
    let required: Bool
}

struct SinkAttachment {
    let fieldKey: String
    let sourceURL: URL  // local file path; remote URLs are out of scope for v1
}

enum SinkUpsertResult {
    case inserted(recordId: String)
    case updated(recordId: String)
    case skipped(reason: String)
}

struct SinkBulkInsertResult {
    let insertedRecordIds: [String]
    let failures: [(index: Int, message: String)]
}
