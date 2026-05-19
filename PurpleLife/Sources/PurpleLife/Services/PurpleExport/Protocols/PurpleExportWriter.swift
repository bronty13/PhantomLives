import Foundation

/// What a destination-format writer must implement. One conformer
/// per format (CSV / JSON / XML / Markdown / HTML / PDF in Phase 4).
/// Writers are stateless value-shaped — the runner instantiates per
/// export and discards.
protocol PurpleExportWriter: AnyObject {

    /// Which destination format this writer handles. The runner uses
    /// this to dispatch + the wizard's format picker uses this for
    /// the UI listing.
    var format: PurpleExport.DestinationFormat { get }

    /// Apply per-format options chosen in the wizard. Phase 4 keeps
    /// this a free-form dict for symmetry with `PurpleImportSourceReader`;
    /// a typed `Options` companion is a candidate Phase 4.5 refactor
    /// if it becomes painful.
    func setOptions(_ options: PurpleExport.FormatOptions)

    /// Render the export. The writer receives the type metadata, the
    /// fields the user picked (with header overrides), and the
    /// record stream. Writes to `destination`. Returns the bytes
    /// actually written so the runner can report total in the
    /// `finished` summary.
    func write(
        type: SourceTypeInfo,
        fields: [SourceFieldInfo],
        selections: [PurpleExport.FieldSelection],
        records: [SourceRecord],
        linkResolver: (String) -> String?,
        attachmentResolver: (String) -> String?,
        to destination: URL
    ) throws -> Int
}
