import Foundation
import ZIPFoundation

/// Word (.docx) reader for Purple Import — Phase 5, text-only single
/// record.
///
/// Locked v1 scope (see HANDOFF 2026-05-19): one record per document,
/// the entire extracted text under `.path("$._body")`. We do NOT
/// parse:
///   • Tables (`<w:tbl>`, including `<w:vMerge>` / `<w:gridSpan>`)
///   • Track-changes / revisions (`<w:ins>` / `<w:del>`)
///   • Comments (`<w:commentRangeStart>`)
///   • AlternateContent fallbacks
///   • Embedded images, OLE objects, or charts
/// All of these are known-hard CS problems that commercial tools
/// spend years on. v1 is paragraph-concatenated text — readable,
/// importable, and good enough to land a record. Table extraction
/// graduates to its own Phase 7 design doc when a real motivating
/// document arrives.
///
/// Mechanism: unzip the .docx (it's an OOXML package), parse
/// `word/document.xml` with `XMLParser`, gather `<w:t>` text content,
/// emit a paragraph break on each `<w:p>` close. Soft line-breaks
/// (`<w:br/>`) become single newlines; tab marks (`<w:tab/>`) become
/// literal tabs.
final class DOCXReader: PurpleImportSourceReader {

    var format: PurpleImport.SourceFormat { .docx }

    private var paragraphSeparator: String = "\n\n"

    func setOptions(_ options: [String: Any]) {
        if let s = options["paragraphSeparator"] as? String {
            self.paragraphSeparator = s
        }
    }

    // MARK: - PurpleImportSourceReader

    func probe(_ source: PurpleImport.SourceInput) async throws -> PurpleImport.SourceShape {
        let body = try extractText(from: source)
        return .document(richText: body)
    }

    func preview(_ source: PurpleImport.SourceInput, sampleSize _: Int) async throws -> PurpleImport.SourcePreview {
        let body = try extractText(from: source)
        let row = PurpleImport.SourceRow(
            cells: [.path("$._body"): body],
            rowIndex: 0
        )
        return PurpleImport.SourcePreview(
            shape: .document(richText: body),
            sampleRows: [row],
            totalRows: 1
        )
    }

    func read(_ source: PurpleImport.SourceInput) -> AsyncThrowingStream<PurpleImport.SourceRow, Error> {
        AsyncThrowingStream { continuation in
            do {
                let body = try self.extractText(from: source)
                continuation.yield(PurpleImport.SourceRow(
                    cells: [.path("$._body"): body],
                    rowIndex: 0
                ))
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    // MARK: - Text extraction

    func extractText(from source: PurpleImport.SourceInput) throws -> String {
        let documentXMLData = try readDocumentXML(from: source)
        let collector = DOCXBodyParser(paragraphSeparator: paragraphSeparator)
        let parser = XMLParser(data: documentXMLData)
        parser.delegate = collector
        parser.shouldProcessNamespaces = true
        guard parser.parse() else {
            throw DOCXReaderError.parseFailed(parser.parserError?.localizedDescription ?? "unknown")
        }
        return collector.finalText()
    }

    /// Open the .docx (a ZIP package) and pull out `word/document.xml`.
    /// Falls back to the deprecated failable Archive init only for the
    /// `Data` source path; the `URL` path uses the throwing init that
    /// ZIPFoundation 0.9.20 recommends.
    private func readDocumentXML(from source: PurpleImport.SourceInput) throws -> Data {
        let archive: Archive
        do {
            switch source {
            case .url(let url):
                archive = try Archive(url: url, accessMode: .read)
            case .data(let data, _):
                archive = try Archive(data: data, accessMode: .read)
            }
        } catch {
            throw DOCXReaderError.openFailed(error.localizedDescription)
        }
        guard let entry = archive["word/document.xml"] else {
            throw DOCXReaderError.missingDocumentXML
        }
        var bytes = Data()
        _ = try archive.extract(entry, consumer: { chunk in
            bytes.append(chunk)
        })
        return bytes
    }
}

// MARK: - XMLParser delegate

/// Walks `word/document.xml`. We only care about a tiny subset of
/// the schema:
///   • Inside `<w:p>` we collect a paragraph buffer.
///   • Inside `<w:t>` (only when nested within a `<w:p>`) we capture
///     the literal text. We also accept `<w:t xml:space="preserve">`.
///   • `<w:br/>` adds a single newline mid-paragraph.
///   • `<w:tab/>` adds a literal tab.
/// We skip everything else — including everything under `<w:tbl>` —
/// per the locked v1 scope.
private final class DOCXBodyParser: NSObject, XMLParserDelegate {

    private let paragraphSeparator: String
    private var paragraphs: [String] = []
    private var currentParagraph: String = ""
    private var inParagraph: Bool = false
    private var inTextRun: Bool = false
    // Counter for nested `<w:tbl>` openings — when > 0 we ignore
    // every text node until the table closes. Counts opens/closes so
    // nested tables (rare but legal) don't bleed into the body.
    private var tableDepth: Int = 0

    init(paragraphSeparator: String) {
        self.paragraphSeparator = paragraphSeparator
    }

    func finalText() -> String {
        var all = paragraphs
        // If the document closed mid-paragraph (rare; means the close
        // tag was malformed), still preserve the buffer.
        if !currentParagraph.isEmpty { all.append(currentParagraph) }
        return all.joined(separator: paragraphSeparator)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes attributeDict: [String: String] = [:]) {
        // The `namespaceURI` arrives as the WordprocessingML namespace
        // when `shouldProcessNamespaces == true`; we match on the
        // local name only.
        switch elementName {
        case "tbl":
            tableDepth += 1
        case "p":
            if tableDepth == 0 {
                inParagraph = true
                currentParagraph = ""
            }
        case "t":
            if tableDepth == 0 && inParagraph { inTextRun = true }
        case "br":
            if tableDepth == 0 && inParagraph { currentParagraph.append("\n") }
        case "tab":
            if tableDepth == 0 && inParagraph { currentParagraph.append("\t") }
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard tableDepth == 0, inParagraph, inTextRun else { return }
        currentParagraph.append(string)
    }

    func parser(_ parser: XMLParser, didEndElement elementName: String,
                namespaceURI: String?, qualifiedName: String?) {
        switch elementName {
        case "tbl":
            if tableDepth > 0 { tableDepth -= 1 }
        case "p":
            if tableDepth == 0 && inParagraph {
                paragraphs.append(currentParagraph)
                currentParagraph = ""
                inParagraph = false
            }
        case "t":
            inTextRun = false
        default:
            break
        }
    }
}

// MARK: - Errors

enum DOCXReaderError: LocalizedError {
    case openFailed(String)
    case missingDocumentXML
    case parseFailed(String)

    var errorDescription: String? {
        switch self {
        case .openFailed(let detail):
            return "Couldn't open .docx (not a valid OOXML package): \(detail)"
        case .missingDocumentXML:
            return "This .docx doesn't contain word/document.xml. The file may not be a Word document — some apps export .docx-named files that don't follow the OOXML spec."
        case .parseFailed(let detail):
            return "Couldn't parse word/document.xml: \(detail)"
        }
    }
}
