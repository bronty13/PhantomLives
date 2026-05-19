import Foundation
import GRDB

/// Concrete `PurpleExportSource` for PurpleLife. The one file that
/// knows both the protocol AND the host's `SchemaRegistry` /
/// `ObjectEngine` — symmetric with `PurpleLifeSink` on the import
/// side. Deleting it would unblock extraction to a sibling SPM
/// package later.
@MainActor
final class PurpleLifeSource: PurpleExportSource {

    private let schema: SchemaRegistry

    init(schema: SchemaRegistry) {
        self.schema = schema
    }

    // MARK: - Schema introspection

    func listTypes() throws -> [SourceTypeInfo] {
        schema.types.map { t in
            SourceTypeInfo(
                id: t.id,
                name: t.name,
                pluralName: t.pluralName,
                systemImage: t.systemImage,
                isVault: t.isVault
            )
        }
    }

    func listFields(typeId: String) throws -> [SourceFieldInfo] {
        guard let t = schema.type(id: typeId) else { return [] }
        return t.fields.map { f in
            SourceFieldInfo(
                key: f.key,
                name: f.name,
                kind: f.kind,
                options: f.options
            )
        }
    }

    // MARK: - Record reads

    func fetchRecords(typeId: String, selector: PurpleExport.RecordSelector) throws -> [SourceRecord] {
        let raws = try ObjectEngine.fetch(typeId: typeId)
        // Phase 4 supports `.all`; `.savedSearch` is staged for
        // Phase 4.5 once the search-filter integration lands.
        let filtered: [ObjectRecord]
        switch selector {
        case .all:
            filtered = raws
        case .savedSearch:
            // Fall back to all-records for now. The wizard's
            // PickRecords step grey-flags the saved-search option
            // until this is wired.
            filtered = raws
        }
        return filtered.map { r in
            SourceRecord(
                id: r.id,
                typeId: r.typeId,
                createdAt: r.createdAt,
                updatedAt: r.updatedAt,
                fields: r.fields()
            )
        }
    }

    // MARK: - Resolvers

    func resolveLinkedTitle(recordId: String) -> String? {
        ObjectEngine.resolveLinkedTitle(recordId: recordId)
    }

    func resolveAttachmentLabel(sha256: String) -> String? {
        // Same query AttachmentService.fileURL uses internally —
        // surface the row's stored filename. If sha-lookup ever
        // becomes a hot path we can lift it into a shared helper.
        do {
            let row = try DatabaseService.shared.dbPool.read { db in
                try Attachment.filter(Column("sha256") == sha256).fetchOne(db)
            }
            return row?.filename
        } catch {
            return nil
        }
    }
}
