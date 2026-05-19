import Foundation

/// What a host application must implement so Purple Export can read
/// records out of it. PurpleLife's concrete adapter is
/// `Sources/PurpleLifeSource.swift`; a sibling PhantomLives app would
/// write its own conformer against its own record store.
///
/// Symmetric with `PurpleImportSink`: same string-keyed everything,
/// same `@MainActor` isolation (PurpleLife's stores are MainActor —
/// a Timeliner-shaped sibling would be too).
@MainActor
protocol PurpleExportSource: AnyObject {

    /// Every type the source can export from. Vault types are
    /// included so the wizard can offer them when the Vault is
    /// unlocked; the wizard itself gates the surface UI on
    /// `AppState.vaultRevealed`.
    func listTypes() throws -> [SourceTypeInfo]

    /// Fields on one type, in display order.
    func listFields(typeId: String) throws -> [SourceFieldInfo]

    /// Fetch every record of a given type. Phase 4 reads the whole
    /// set into memory before writing — fine for personal-scale
    /// row counts (<100k); streaming-by-page is a future
    /// optimization if needed.
    func fetchRecords(typeId: String, selector: PurpleExport.RecordSelector) throws -> [SourceRecord]

    /// Resolve a `.link` field's stored record-id into a
    /// human-readable label (typically the linked record's primary
    /// field). `nil` when the id doesn't resolve — writers render
    /// that as an empty string.
    func resolveLinkedTitle(recordId: String) -> String?

    /// Resolve a `.attachment` field's stored sha256 into a label
    /// (typically the filename). `nil` when the sha doesn't resolve.
    func resolveAttachmentLabel(sha256: String) -> String?
}

// MARK: - Value types

struct SourceTypeInfo: Hashable {
    let id: String
    let name: String
    let pluralName: String
    let systemImage: String
    let isVault: Bool
}

struct SourceFieldInfo: Hashable, Identifiable {
    let key: String
    let name: String
    let kind: FieldKind
    let options: [FieldOption]
    var id: String { key }
}

/// One record handed to a writer. Carries the typed columns
/// PurpleLife exposes plus the decoded `fields_json` blob as a
/// dictionary keyed by `FieldDef.key`. Writers project this through
/// `FieldSelection`'s field-key + header-override pairs.
struct SourceRecord {
    let id: String
    let typeId: String
    let createdAt: String      // ISO-8601
    let updatedAt: String      // ISO-8601
    let fields: [String: Any]  // dynamic shape, keyed by field key
}
