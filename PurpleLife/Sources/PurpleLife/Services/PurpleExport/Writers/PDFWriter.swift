import Foundation

/// PDF writer. Renders the HTMLWriter's output through
/// `ExportService.renderHTMLToPDF` (a WKWebView pipeline) — same
/// path the legacy single-type "Export PDF" toolbar item uses, so
/// the visual output is consistent.
///
/// Synchronous façade over an async render pipeline: WKWebView's
/// `pdf(configuration:)` is async and main-actor-bound, so the
/// runner's `write(...)` call has to bridge with a checked
/// continuation. Acceptable here because we already serialize one
/// export at a time.
@MainActor
final class PDFWriter: PurpleExportWriter {

    var format: PurpleExport.DestinationFormat { .pdf }

    private var options = PurpleExport.FormatOptions()
    private let htmlWriter = HTMLWriter()

    func setOptions(_ options: PurpleExport.FormatOptions) {
        self.options = options
        htmlWriter.setOptions(options)
    }

    func write(
        type: SourceTypeInfo,
        fields: [SourceFieldInfo],
        selections: [PurpleExport.FieldSelection],
        records: [SourceRecord],
        linkResolver: (String) -> String?,
        attachmentResolver: (String) -> String?,
        to destination: URL
    ) throws -> Int {
        let html = htmlWriter.renderHTML(
            type: type,
            fields: fields,
            selections: selections,
            records: records,
            linkResolver: linkResolver,
            attachmentResolver: attachmentResolver
        )
        // Bridge the async WKWebView render to a sync return for
        // PurpleExportWriter's signature. The semaphore is awkward
        // but Phase 4 keeps writers synchronous to match the
        // simpler `PurpleImportSourceReader.read` shape; a
        // streaming-async revamp can come in Phase 6.
        let sem = DispatchSemaphore(value: 0)
        var output: Result<Data, Error> = .failure(PDFWriterError.notRendered)
        Task {
            do {
                let data = try await ExportService.renderHTMLToPDF(html: html)
                output = .success(data)
            } catch {
                output = .failure(error)
            }
            sem.signal()
        }
        // Pump the run loop while the async task runs. WKWebView
        // navigation callbacks fire on the main thread, so we have
        // to keep it spinning rather than block it outright.
        while sem.wait(timeout: .now() + 0.01) == .timedOut {
            RunLoop.main.run(mode: .default, before: Date(timeIntervalSinceNow: 0.05))
        }
        switch output {
        case .success(let data):
            try data.write(to: destination, options: .atomic)
            return data.count
        case .failure(let err):
            throw err
        }
    }
}

enum PDFWriterError: LocalizedError {
    case notRendered

    var errorDescription: String? {
        switch self {
        case .notRendered:
            return "PDF render failed — the WKWebView pipeline didn't produce output."
        }
    }
}
