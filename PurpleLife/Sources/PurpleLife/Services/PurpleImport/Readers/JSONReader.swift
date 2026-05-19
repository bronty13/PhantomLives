import Foundation

/// JSON reader for Purple Import. Backed by `JSONSerialization`.
///
/// Three shapes are handled:
///
/// 1. **Array of objects at the top level** — `[ {…}, {…} ]`. Each
///    array element becomes one source row; keys become path
///    locators (`$.name`, `$.address.city`).
/// 2. **NDJSON / JSON Lines** — one object per line. Detected by
///    `.ndjson` extension or by the first non-whitespace byte being
///    `{` followed later by `}\n{`. Each line is one row.
/// 3. **Object with an array somewhere inside** — the user picks a
///    "root path" via the wizard's ConfigureSource step (e.g.
///    `$.results.records`). The reader evaluates that path and
///    treats the result as case 1.
///
/// Path expression syntax (a JSONPath-lite subset):
///   • `$` — the root
///   • `.<key>` — object child
///   • `[<index>]` — array element (0-based)
///   • `[*]` — every element (for the row-fan-out path during read)
///
/// Wildcards inside field-mapping paths (`$.tags[*]`) yield arrays.
final class JSONReader: PurpleImportSourceReader {

    var format: PurpleImport.SourceFormat { .json }

    /// Path expression the reader treats as the row collection. `$`
    /// means "the top-level value, which must be an array."
    private var rootPath: String = "$"
    private var ndjson: Bool = false

    func setOptions(_ options: [String: Any]) {
        if let s = options["rootPath"] as? String, !s.isEmpty {
            self.rootPath = s
        }
        if let b = options["ndjson"] as? Bool {
            self.ndjson = b
        }
    }

    // MARK: - PurpleImportSourceReader

    func probe(_ source: PurpleImport.SourceInput) async throws -> PurpleImport.SourceShape {
        let preview = try await preview(source, sampleSize: 50)
        return preview.shape
    }

    func preview(_ source: PurpleImport.SourceInput, sampleSize: Int) async throws -> PurpleImport.SourcePreview {
        let data = try loadData(source)
        if ndjson || isLikelyNDJSON(data, source: source) {
            let rows = try parseNDJSON(data, max: sampleSize)
            return previewFromObjects(rows)
        }
        let parsed = try JSONSerialization.jsonObject(
            with: data,
            options: [.fragmentsAllowed]
        )
        let root = try Self.evaluatePath(rootPath, on: parsed)
        if let array = root as? [Any] {
            let slice = Array(array.prefix(sampleSize))
            let objects = slice.compactMap { $0 as? [String: Any] }
            return previewFromObjects(objects, totalRows: array.count)
        }
        // Single object — surface as a tree shape with the visible
        // top-level keys. The wizard's "Create new type from this
        // source" step picks one record from this.
        if let dict = root as? [String: Any] {
            let keys = dict.keys.sorted()
            return PurpleImport.SourcePreview(
                shape: .tree(rootPaths: keys.map { "$.\($0)" }),
                sampleRows: [previewSingleObjectRow(dict)],
                totalRows: 1
            )
        }
        // A bare value (string/number) at the root is unusual but
        // not an error — surface as a one-row, one-cell document.
        return PurpleImport.SourcePreview(
            shape: .tree(rootPaths: ["$"]),
            sampleRows: [PurpleImport.SourceRow(cells: [.path("$"): root], rowIndex: 0)],
            totalRows: 1
        )
    }

    func read(_ source: PurpleImport.SourceInput) -> AsyncThrowingStream<PurpleImport.SourceRow, Error> {
        AsyncThrowingStream { continuation in
            do {
                let data = try loadData(source)
                if ndjson || isLikelyNDJSON(data, source: source) {
                    let objects = try parseNDJSON(data, max: nil)
                    for (i, obj) in objects.enumerated() {
                        if Task.isCancelled { break }
                        continuation.yield(rowFromObject(obj, index: i))
                    }
                    continuation.finish()
                    return
                }
                let parsed = try JSONSerialization.jsonObject(
                    with: data,
                    options: [.fragmentsAllowed]
                )
                let root = try Self.evaluatePath(rootPath, on: parsed)
                if let array = root as? [Any] {
                    for (i, value) in array.enumerated() {
                        if Task.isCancelled { break }
                        let obj = value as? [String: Any] ?? ["value": value]
                        continuation.yield(rowFromObject(obj, index: i))
                    }
                } else if let dict = root as? [String: Any] {
                    continuation.yield(rowFromObject(dict, index: 0))
                }
                continuation.finish()
            } catch {
                continuation.finish(throwing: error)
            }
        }
    }

    // MARK: - Path evaluation

    /// Evaluate a JSONPath-lite expression against a parsed JSON
    /// value. Returns the resulting subtree (Any) or throws if the
    /// path doesn't resolve.
    static func evaluatePath(_ path: String, on root: Any) throws -> Any {
        guard path == "$" || path.hasPrefix("$") else {
            throw NSError(
                domain: "PurpleImport.JSONPath",
                code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Path must start with $: \(path)"]
            )
        }
        if path == "$" { return root }
        var current: Any = root
        var remaining = path
        remaining.removeFirst()  // drop leading $
        let tokens = tokenize(remaining)
        for token in tokens {
            switch token {
            case .key(let k):
                guard let dict = current as? [String: Any], let v = dict[k] else {
                    throw NSError(
                        domain: "PurpleImport.JSONPath",
                        code: 2,
                        userInfo: [NSLocalizedDescriptionKey: "Missing key '\(k)' in path \(path)"]
                    )
                }
                current = v
            case .index(let i):
                guard let arr = current as? [Any], i >= 0, i < arr.count else {
                    throw NSError(
                        domain: "PurpleImport.JSONPath",
                        code: 3,
                        userInfo: [NSLocalizedDescriptionKey: "Index \(i) out of range in path \(path)"]
                    )
                }
                current = arr[i]
            case .wildcard:
                guard let arr = current as? [Any] else {
                    throw NSError(
                        domain: "PurpleImport.JSONPath",
                        code: 4,
                        userInfo: [NSLocalizedDescriptionKey: "[*] on non-array in path \(path)"]
                    )
                }
                current = arr
            }
        }
        return current
    }

    private enum Token: Equatable {
        case key(String)
        case index(Int)
        case wildcard
    }

    private static func tokenize(_ s: String) -> [Token] {
        var tokens: [Token] = []
        var i = s.startIndex
        while i < s.endIndex {
            let c = s[i]
            if c == "." {
                i = s.index(after: i)
                var name = ""
                while i < s.endIndex, s[i] != ".", s[i] != "[" {
                    name.append(s[i])
                    i = s.index(after: i)
                }
                if !name.isEmpty { tokens.append(.key(name)) }
            } else if c == "[" {
                i = s.index(after: i)
                var body = ""
                while i < s.endIndex, s[i] != "]" {
                    body.append(s[i])
                    i = s.index(after: i)
                }
                if i < s.endIndex { i = s.index(after: i) }  // consume ]
                if body == "*" {
                    tokens.append(.wildcard)
                } else if let n = Int(body) {
                    tokens.append(.index(n))
                } else if !body.isEmpty {
                    // Bracketed string key, e.g. ["full name"]
                    let cleaned = body.trimmingCharacters(in: CharacterSet(charactersIn: "\"'"))
                    tokens.append(.key(cleaned))
                }
            } else {
                i = s.index(after: i)
            }
        }
        return tokens
    }

    // MARK: - Helpers

    private func loadData(_ source: PurpleImport.SourceInput) throws -> Data {
        switch source {
        case .url(let url):  return try Data(contentsOf: url)
        case .data(let d, _): return d
        }
    }

    private func isLikelyNDJSON(_ data: Data, source: PurpleImport.SourceInput) -> Bool {
        if case .url(let url) = source, url.pathExtension.lowercased() == "ndjson" {
            return true
        }
        // Heuristic: starts with `{` and contains `}\n{` somewhere
        // near the start.
        guard let prefix = String(data: data.prefix(1024), encoding: .utf8) else { return false }
        let trimmed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.hasPrefix("{") else { return false }
        return prefix.contains("}\n{") || prefix.contains("}\r\n{")
    }

    private func parseNDJSON(_ data: Data, max: Int?) throws -> [[String: Any]] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        var out: [[String: Any]] = []
        for line in text.split(whereSeparator: { $0.isNewline }) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty { continue }
            guard let lineData = trimmed.data(using: .utf8),
                  let obj = (try? JSONSerialization.jsonObject(with: lineData)) as? [String: Any]
            else { continue }
            out.append(obj)
            if let cap = max, out.count >= cap { break }
        }
        return out
    }

    private func previewFromObjects(_ objects: [[String: Any]], totalRows: Int? = nil) -> PurpleImport.SourcePreview {
        // Union of keys across the sample. Sorted for deterministic
        // ordering in the mapping UI.
        var keySet: Set<String> = []
        for obj in objects {
            for k in obj.keys { keySet.insert(k) }
        }
        let keys = keySet.sorted()
        let rows: [PurpleImport.SourceRow] = objects.enumerated().map { (i, obj) in
            rowFromObject(obj, index: i, withKeys: keys)
        }
        // Infer kinds per top-level key from the sample.
        var kinds: [String: FieldKind] = [:]
        for k in keys {
            let samples = rows.compactMap { $0.cell(at: .path("$.\(k)")) }
            kinds[k] = FieldValueCoercer.inferKind(samples: samples)
        }
        // Tree-shape preview, but with the keys exposed as a quick
        // tabular surface for the wizard's mapping table — it
        // renders the same way for tabular and tree at the per-row
        // level; only the path-vs-column dropdown differs.
        return PurpleImport.SourcePreview(
            shape: .tree(rootPaths: keys.map { "$.\($0)" }),
            sampleRows: rows,
            totalRows: totalRows
        )
    }

    private func rowFromObject(_ obj: [String: Any], index: Int, withKeys keys: [String]? = nil) -> PurpleImport.SourceRow {
        let pathKeys = keys ?? obj.keys.sorted()
        var cells: [PurpleImport.SourceLocator: Any] = [:]
        for k in pathKeys {
            cells[.path("$.\(k)")] = obj[k] ?? NSNull()
        }
        return PurpleImport.SourceRow(cells: cells, rowIndex: index)
    }

    private func previewSingleObjectRow(_ obj: [String: Any]) -> PurpleImport.SourceRow {
        rowFromObject(obj, index: 0)
    }
}
