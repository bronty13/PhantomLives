import Foundation

/// PurpleLife's concrete `PurpleImportSink`. The one file that knows
/// both the engine protocol AND the host app's record store; deletes
/// would unblock extraction to a sibling SPM package later.
///
/// Lifecycle: created by `AppState` once SchemaRegistry, ObjectEngine
/// hooks, AttachmentService, and KeyStore are all wired. The wizard
/// is given `appState.purpleImportSink` and passes it through to the
/// `ImportRunner`.
@MainActor
final class PurpleLifeSink: PurpleImportSink {

    private let schema: SchemaRegistry

    init(schema: SchemaRegistry) {
        self.schema = schema
    }

    // MARK: - Schema introspection

    func listTypes() throws -> [SinkTypeInfo] {
        schema.types.map { t in
            SinkTypeInfo(
                id: t.id,
                name: t.name,
                pluralName: t.pluralName,
                systemImage: t.systemImage,
                isVault: t.isVault
            )
        }
    }

    func listFields(typeId: String) throws -> [SinkFieldInfo] {
        guard let t = schema.type(id: typeId) else { return [] }
        return t.fields.map { f in
            SinkFieldInfo(
                key: f.key,
                name: f.name,
                kind: f.kind,
                options: f.options,
                required: f.required
            )
        }
    }

    // MARK: - Schema mutation (inline edit during mapping)

    func createType(_ proposal: SinkTypeProposal) throws -> String {
        let fields = proposal.fields.map { p in
            FieldDef.make(
                name: p.name,
                kind: p.kind,
                options: p.options,
                required: p.required
            )
        }
        let id = UUID().uuidString
        let type = ObjectType(
            id: id,
            name: proposal.name,
            pluralName: proposal.pluralName,
            systemImage: proposal.systemImage,
            colorHex: proposal.colorHex,
            fields: fields,
            builtIn: false,
            primaryFieldKey: fields.first?.key,
            kanbanGroupKey: nil,
            calendarDateKey: nil,
            galleryAttachmentKey: nil,
            updatedAt: nil,
            isVault: proposal.isVault,
            tags: []
        )
        schema.upsertType(type)
        return id
    }

    func addField(typeId: String, _ proposal: SinkFieldProposal) throws -> String {
        let field = FieldDef.make(
            name: proposal.name,
            kind: proposal.kind,
            options: proposal.options,
            required: proposal.required
        )
        schema.addField(field, toTypeId: typeId)
        return field.key
    }

    // MARK: - Record writes

    func upsert(
        typeId: String,
        keyFieldKey: String?,
        values: [String: Any],
        attachments: [SinkAttachment]
    ) throws -> SinkUpsertResult {
        // Upsert path. When keyFieldKey is set, look for an existing
        // record with the same value on that key and update it; else
        // create. Match comparison goes through the cell's stringified
        // form — same shape `FieldDisplay.title` already uses for
        // equality across stored vs UI representations.
        var record: ObjectRecord?
        if let key = keyFieldKey, let candidateValue = values[key] {
            let candidateString = stringValue(candidateValue)
            let existing = try ObjectEngine.fetch(typeId: typeId)
            record = existing.first { r in
                guard let v = r.fields()[key] else { return false }
                return stringValue(v) == candidateString
            }
        }

        if let existing = record {
            let updated = try ObjectEngine.update(existing, fields: values)
            try attachAll(attachments, toRecordId: updated.id)
            return .updated(recordId: updated.id)
        }
        let created = try ObjectEngine.create(typeId: typeId, fields: values)
        try attachAll(attachments, toRecordId: created.id)
        return .inserted(recordId: created.id)
    }

    func bulkInsert(
        typeId: String,
        rows: [[String: Any]]
    ) throws -> SinkBulkInsertResult {
        let result = try ObjectEngine.bulkInsert(typeId: typeId, rows: rows)
        return SinkBulkInsertResult(
            insertedRecordIds: result.inserted.map(\.id),
            failures: result.errors.map { (index: $0.index, message: $0.message) }
        )
    }

    // MARK: - Helpers

    private func attachAll(_ attachments: [SinkAttachment], toRecordId recordId: String) throws {
        guard !attachments.isEmpty else { return }
        for a in attachments {
            let added = try AttachmentService.add(
                from: a.sourceURL,
                parentObjectId: recordId,
                fieldKey: a.fieldKey
            )
            // Mirror the attachment's sha256 into the record's field
            // value, same pattern as the existing AttachmentService
            // README and the WeightCSVImporter precedent.
            if let record = try ObjectEngine.fetch(id: recordId) {
                _ = try ObjectEngine.update(record, fields: [a.fieldKey: added.sha256])
            }
        }
    }

    private func stringValue(_ v: Any) -> String {
        if let s = v as? String { return s }
        if let n = v as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            let d = n.doubleValue
            if d.rounded() == d, abs(d) < 1e15 { return String(Int64(d)) }
            return String(d)
        }
        return String(describing: v)
    }
}
