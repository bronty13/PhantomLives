import Foundation

/// What a source-format adapter must implement so Purple Import can
/// preview and read from it. One conformer per format (CSV, JSON,
/// XML, …). The wizard picks the right reader by file extension or
/// by user-chosen format in the source-picker step.
///
/// All probes / previews / reads are async — large files (XLSX,
/// long PDFs) can take long enough that running on the main actor
/// would block the UI. Implementations are free to be MainActor-free.
protocol PurpleImportSourceReader: AnyObject {

    /// Human-readable label shown in the wizard's format picker.
    var format: PurpleImport.SourceFormat { get }

    /// Per-format options the user can tweak (CSV delimiter, JSON
    /// root path, XLSX sheet name, …). The reader stores them inside
    /// itself and applies them on subsequent `probe`/`preview`/`read`
    /// calls. Phase 1 keeps this a free-form dict to avoid an
    /// associated-type explosion across readers; Phase 2 may
    /// introduce a typed `Options` companion if it becomes painful.
    func setOptions(_ options: [String: Any])

    /// Inspect the source enough to decide tabular vs tree and
    /// surface the column / root-path list. Cheap: should sip the
    /// first few KB only.
    func probe(_ source: PurpleImport.SourceInput) async throws -> PurpleImport.SourceShape

    /// Decode up to `sampleSize` rows. The reader is allowed (and
    /// expected) to return fewer rows than asked for if the source
    /// is shorter, and to leave `SourcePreview.totalRows = nil` if
    /// counting requires a full second pass.
    func preview(_ source: PurpleImport.SourceInput, sampleSize: Int) async throws -> PurpleImport.SourcePreview

    /// Read every row. The runner consumes this and pumps rows
    /// through the coercer + sink. Cancellation: the stream's task
    /// is cancellable; readers must check `Task.isCancelled` at row
    /// boundaries.
    func read(_ source: PurpleImport.SourceInput) -> AsyncThrowingStream<PurpleImport.SourceRow, Error>
}
