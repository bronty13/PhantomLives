import Foundation

/// XML reader for Purple Import. Backed by Foundation's `XMLParser`.
///
/// XML's shape is fundamentally tree-of-elements. The reader parses
/// the document into a nested dictionary structure once (attributes
/// land under `@attr` keys; child elements with the same name
/// collapse into arrays; leaf text lands at `#text`), then evaluates
/// the same JSONPath-lite expressions `JSONReader` supports.
///
/// Default behavior:
///   • Look for a repeating child element under the root (the user's
///     "records collection"). When found, fan out one source row per
///     element with `.path("$.field")` locators per attribute / child.
///   • When no repeating child is detected, surface the root element
///     as a single record.
///
/// The user can override the row-fan-out path via the `rootPath`
/// option (`$.catalog.books[*]`).
final class XMLReader: PurpleImportSourceReader {

    var format: PurpleImport.SourceFormat { .xml }

    private var rootPath: String?

    func setOptions(_ options: [String: Any]) {
        if let s = options["rootPath"] as? String, !s.isEmpty {
            self.rootPath = s
        }
    }

    // MARK: - PurpleImportSourceReader

    func probe(_ source: PurpleImport.SourceInput) async throws -> PurpleImport.SourceShape {
        let preview = try await preview(source, sampleSize: 50)
        return preview.shape
    }

    func preview(_ source: PurpleImport.SourceInput, sampleSize: Int) async throws -> PurpleImport.SourcePreview {
        let parsed = try await parse(source)
        let collection = resolveCollection(in: parsed)
        let slice = Array(collection.prefix(sampleSize))
        let objects = slice.compactMap { $0 as? [String: Any] }

        // Union of keys across the sample for stable ordering.
        var keySet: Set<String> = []
        for obj in objects { for k in obj.keys { keySet.insert(k) } }
        let keys = keySet.sorted()

        let rows: [PurpleImport.SourceRow] = objects.enumerated().map { (i, obj) in
            var cells: [PurpleImport.SourceLocator: Any] = [:]
            for k in keys { cells[.path("$.\(k)")] = obj[k] ?? "" }
            return PurpleImport.SourceRow(cells: cells, rowIndex: i)
        }

        var kinds: [String: FieldKind] = [:]
        for k in keys {
            let samples = rows.compactMap { $0.cell(at: .path("$.\(k)")) }
            kinds[k] = FieldValueCoercer.inferKind(samples: samples)
        }
        _ = kinds  // surfaced for future tree-shape inference hint

        return PurpleImport.SourcePreview(
            shape: .tree(rootPaths: keys.map { "$.\($0)" }),
            sampleRows: rows,
            totalRows: collection.count
        )
    }

    func read(_ source: PurpleImport.SourceInput) -> AsyncThrowingStream<PurpleImport.SourceRow, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let parsed = try await self.parse(source)
                    let collection = self.resolveCollection(in: parsed)
                    for (i, value) in collection.enumerated() {
                        if Task.isCancelled { break }
                        let obj = value as? [String: Any] ?? ["value": value]
                        var cells: [PurpleImport.SourceLocator: Any] = [:]
                        for (k, v) in obj { cells[.path("$.\(k)")] = v }
                        continuation.yield(PurpleImport.SourceRow(cells: cells, rowIndex: i))
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    // MARK: - Parsing

    private func parse(_ source: PurpleImport.SourceInput) async throws -> [String: Any] {
        let data: Data
        switch source {
        case .url(let url):   data = try Data(contentsOf: url)
        case .data(let d, _): data = d
        }
        return try await withCheckedThrowingContinuation { continuation in
            let parser = XMLParser(data: data)
            let delegate = XMLToDictDelegate()
            parser.delegate = delegate
            if parser.parse() {
                continuation.resume(returning: delegate.result)
            } else {
                continuation.resume(throwing: parser.parserError ?? NSError(
                    domain: "PurpleImport.XML", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "XML parse failed"]
                ))
            }
        }
    }

    /// Pick the collection of records to fan rows out from. The
    /// explicit rootPath wins; otherwise we look for the largest
    /// repeating child element under the root (the "<books><book>…</book><book>…</book></books>"
    /// shape) and fall back to a single-record list for a flat
    /// document.
    private func resolveCollection(in tree: [String: Any]) -> [Any] {
        if let rp = rootPath {
            return collection(at: rp, in: tree)
        }
        // Root has a single top-level element. Look inside it for a
        // repeating child.
        guard let rootKey = tree.keys.first, let inner = tree[rootKey] as? [String: Any] else {
            return [tree]
        }
        // The largest array-valued child wins.
        let candidates: [(String, [Any])] = inner.compactMap { (k, v) in
            if let arr = v as? [Any], arr.count >= 1 { return (k, arr) }
            return nil
        }
        if let best = candidates.max(by: { $0.1.count < $1.1.count }) {
            return best.1
        }
        return [inner]
    }

    private func collection(at path: String, in tree: [String: Any]) -> [Any] {
        do {
            let value = try JSONReader.evaluatePath(path, on: tree)
            if let arr = value as? [Any] { return arr }
            return [value]
        } catch {
            return []
        }
    }
}

// MARK: - XMLParser → dictionary delegate

/// Builds a nested dictionary from SAX-style parser events. Element
/// children with the same name collapse into arrays under that name.
/// Attributes appear under their attribute name (no `@`-prefix —
/// keeps path expressions clean). Leaf text lands under `#text`; an
/// element with neither attributes nor children collapses to its
/// text string directly.
private final class XMLToDictDelegate: NSObject, XMLParserDelegate {
    var result: [String: Any] = [:]

    private var stack: [(name: String, dict: [String: Any], textBuf: String)] = []

    func parserDidStartDocument(_ parser: XMLParser) {
        stack = []
        result = [:]
    }

    func parser(_ parser: XMLParser,
                didStartElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?,
                attributes attributeDict: [String: String] = [:]) {
        var entry: [String: Any] = [:]
        for (k, v) in attributeDict { entry[k] = v }
        stack.append((name: elementName, dict: entry, textBuf: ""))
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        guard !stack.isEmpty else { return }
        stack[stack.count - 1].textBuf += string
    }

    func parser(_ parser: XMLParser,
                didEndElement elementName: String,
                namespaceURI: String?,
                qualifiedName qName: String?) {
        guard !stack.isEmpty else { return }
        let frame = stack.removeLast()
        let trimmedText = frame.textBuf.trimmingCharacters(in: .whitespacesAndNewlines)
        let value: Any
        if frame.dict.isEmpty && !trimmedText.isEmpty {
            value = trimmedText
        } else {
            var d = frame.dict
            if !trimmedText.isEmpty { d["#text"] = trimmedText }
            value = d
        }
        if var parent = stack.last {
            // Merge into the parent. If a sibling with the same name
            // already exists, promote to an array.
            if let existing = parent.dict[frame.name] {
                if var arr = existing as? [Any] {
                    arr.append(value)
                    parent.dict[frame.name] = arr
                } else {
                    parent.dict[frame.name] = [existing, value]
                }
            } else {
                parent.dict[frame.name] = value
            }
            stack[stack.count - 1] = parent
        } else {
            result[frame.name] = value
        }
    }
}
