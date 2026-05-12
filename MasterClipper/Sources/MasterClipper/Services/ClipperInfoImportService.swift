import Foundation

/// Parses the plain-text payload produced by the **ClipperInfo** companion
/// web app and computes a per-field diff against the live clips so the
/// importer can show the user exactly what will change before applying.
///
/// Round-trip format (one block per clip, blocks separated by a blank line):
///
///     YYYY-MM-DD-##### - <title> [<persona>]
///     Description: <text or "Blank">
///     Categories: <CSV or "None Defined">
///     Go-live date: <YYYY-MM-DD or "Not set">
///
/// An optional preamble line `Please confirm/provide the following:` is
/// tolerated (and stripped) so payloads pasted verbatim from the **Copy
/// for creator** button in the *Information Needed* report parse without
/// the user having to trim them by hand.
///
/// The parser is intentionally lenient — blocks that don't start with a
/// header line are skipped with no thrown error so a stray paragraph
/// pasted in by accident doesn't kill the whole import.
enum ClipperInfoImportService {

    // MARK: - Parsed entry

    struct ParsedEntry: Hashable {
        let id: String                       // "YYYY-MM-DD-#####"
        let title: String                    // may be "Untitled" if creator left blank
        let personaCode: String
        let description: String              // "" when source said "Blank"
        let categories: [String]             // uppercased, [] when source said "None Defined"
        let goLiveDate: String               // "" when source said "Not set"
    }

    // MARK: - Diff model

    /// One concrete change the user can accept or reject. `categoryAdd`
    /// and `categoryRemove` are emitted *per category* so the user can
    /// take some additions and reject others within the same clip.
    struct FieldChange: Identifiable, Hashable {
        enum Kind: Hashable {
            case title
            case persona
            case description
            case goLiveDate
            case categoryAdd(String)         // category name (uppercase)
            case categoryRemove(String)
        }
        let id = UUID()
        let kind: Kind
        let oldValue: String
        let newValue: String
        var accepted: Bool
    }

    /// Per-clip outcome of the diff. `clip == nil` → the parsed id doesn't
    /// match any clip in the database; surfaced in the UI as "Unknown
    /// ID — skipping". `changes` is empty when the entry is in sync with
    /// the DB (still shown so the user knows it was processed).
    struct ClipDiff: Identifiable, Hashable {
        let id: String                       // == parsed.id
        let parsed: ParsedEntry
        let clip: Clip?                      // nil when not found
        let existingCategories: [String]     // empty when clip nil
        var changes: [FieldChange]

        var hasChanges: Bool { !changes.isEmpty }
        var acceptedChangeCount: Int { changes.filter(\.accepted).count }
        var unknown: Bool { clip == nil }
    }

    // MARK: - Parse

    /// Headers look like `2025-04-12-00031 - Some Title [CoC]`.
    /// `(.+)` greedy on the title means the trailing `[persona]` is
    /// always the last bracketed group on the line.
    private static let headerPattern =
        #"^(\d{4}-\d{2}-\d{2}-\d{5}) - (.+) \[([^\]]+)\]\s*$"#
    private static let preamble = "Please confirm/provide the following:"

    static func parse(_ raw: String) -> [ParsedEntry] {
        var t = raw.replacingOccurrences(of: "\r\n", with: "\n")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        if t.hasPrefix(preamble) {
            t = String(t.dropFirst(preamble.count))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }

        // Walk lines and gather blocks separated by blank (whitespace-only)
        // lines — equivalent to the JS regex split on /\n\s*\n+/ but with
        // a single-pass scan and no regex literal.
        var blocks: [[String]] = []
        var current: [String] = []
        for raw in t.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw).trimmingCharacters(in: CharacterSet(charactersIn: " \t"))
            if line.isEmpty {
                if !current.isEmpty { blocks.append(current); current = [] }
            } else {
                current.append(line)
            }
        }
        if !current.isEmpty { blocks.append(current) }

        var out: [ParsedEntry] = []
        for lines in blocks {
            guard let header = lines.first,
                  let parsed = parseHeader(header)
            else { continue }

            var description = ""
            var categories: [String] = []
            var goLive = ""

            for line in lines.dropFirst() {
                if let v = stripPrefix(line, "Description:") {
                    description = (v == "Blank") ? "" : v
                } else if let v = stripPrefix(line, "Categories:") {
                    if v.isEmpty || v == "None Defined" {
                        categories = []
                    } else {
                        categories = v
                            .split(separator: ",")
                            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
                            .filter { !$0.isEmpty }
                    }
                } else if let v = stripPrefix(line, "Go-live date:") {
                    goLive = (v == "Not set") ? "" : v
                }
            }

            out.append(ParsedEntry(
                id: parsed.id,
                title: parsed.title,
                personaCode: parsed.persona,
                description: description,
                categories: categories,
                goLiveDate: goLive
            ))
        }
        return out
    }

    private static func parseHeader(_ line: String) -> (id: String, title: String, persona: String)? {
        guard let regex = try? NSRegularExpression(pattern: headerPattern) else { return nil }
        let range = NSRange(line.startIndex..., in: line)
        guard let m = regex.firstMatch(in: line, range: range), m.numberOfRanges == 4,
              let idR = Range(m.range(at: 1), in: line),
              let tR  = Range(m.range(at: 2), in: line),
              let pR  = Range(m.range(at: 3), in: line)
        else { return nil }
        return (
            id: String(line[idR]),
            title: String(line[tR]).trimmingCharacters(in: .whitespaces),
            persona: String(line[pR]).trimmingCharacters(in: .whitespaces)
        )
    }

    private static func stripPrefix(_ line: String, _ prefix: String) -> String? {
        guard line.hasPrefix(prefix) else { return nil }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Diff

    /// Build the diff for every parsed entry against the live state. Every
    /// change is pre-checked (`accepted = true`) so the default action is
    /// "apply everything"; the user reviews and unchecks anything they
    /// want to reject.
    @MainActor
    static func diff(entries: [ParsedEntry], appState: AppState) -> [ClipDiff] {
        let clipsById = Dictionary(uniqueKeysWithValues: appState.clips.map { ($0.id, $0) })

        return entries.map { entry in
            guard let clip = clipsById[entry.id] else {
                return ClipDiff(
                    id: entry.id,
                    parsed: entry,
                    clip: nil,
                    existingCategories: [],
                    changes: []
                )
            }

            // Resolve existing category names in the same order setCategories
            // would emit on read — that's the order we'll diff and re-apply.
            let existingIds = (try? DatabaseService.shared.categoryIds(forClip: clip.id)) ?? []
            let existingNames: [String] = existingIds.compactMap { cid in
                appState.categories.first(where: { $0.id == cid })?.name
            }

            var changes: [FieldChange] = []

            // Title — trim before comparing so trailing spaces aren't a "change".
            let oldTitle = clip.title.trimmingCharacters(in: .whitespaces)
            let newTitle = entry.title.trimmingCharacters(in: .whitespaces)
            if oldTitle != newTitle {
                changes.append(FieldChange(
                    kind: .title, oldValue: oldTitle, newValue: newTitle, accepted: true
                ))
            }

            // Persona — case-insensitive.
            let oldPersona = clip.personaCode
            let newPersona = entry.personaCode
            if oldPersona.caseInsensitiveCompare(newPersona) != .orderedSame {
                changes.append(FieldChange(
                    kind: .persona, oldValue: oldPersona, newValue: newPersona, accepted: true
                ))
            }

            // Description — compare with whitespace normalised; an "added
            // trailing newline" isn't a meaningful diff.
            let oldDesc = clip.descriptionRaw.trimmingCharacters(in: .whitespacesAndNewlines)
            let newDesc = entry.description.trimmingCharacters(in: .whitespacesAndNewlines)
            if oldDesc != newDesc {
                changes.append(FieldChange(
                    kind: .description, oldValue: oldDesc, newValue: newDesc, accepted: true
                ))
            }

            // Go-live date — empty means "cleared / not set".
            let oldGoLive = (clip.goLiveDate ?? "").trimmingCharacters(in: .whitespaces)
            let newGoLive = entry.goLiveDate
            if oldGoLive != newGoLive {
                changes.append(FieldChange(
                    kind: .goLiveDate, oldValue: oldGoLive, newValue: newGoLive, accepted: true
                ))
            }

            // Categories — case-insensitive set diff, per-name accept toggles.
            let existingUpper = Set(existingNames.map { $0.uppercased() })
            let parsedUpper   = Set(entry.categories.map { $0.uppercased() })
            let additions = entry.categories.filter { !existingUpper.contains($0.uppercased()) }
            let removals  = existingNames.filter  { !parsedUpper.contains($0.uppercased()) }
            for name in additions {
                changes.append(FieldChange(
                    kind: .categoryAdd(name),
                    oldValue: "",
                    newValue: name,
                    accepted: true
                ))
            }
            for name in removals {
                changes.append(FieldChange(
                    kind: .categoryRemove(name),
                    oldValue: name,
                    newValue: "",
                    accepted: true
                ))
            }

            return ClipDiff(
                id: entry.id,
                parsed: entry,
                clip: clip,
                existingCategories: existingNames,
                changes: changes
            )
        }
    }

    // MARK: - Apply

    struct ApplyResult {
        var clipsTouched: Int = 0
        var fieldChangesApplied: Int = 0
        var categoriesAdded: Int = 0
        var categoriesRemoved: Int = 0
        var categoriesCreated: Int = 0
        var unknownIdsSkipped: Int = 0
        var errors: [String] = []
    }

    /// Apply every accepted change. Diffs whose clip is missing are
    /// counted as `unknownIdsSkipped`. Diffs with no accepted changes
    /// are no-ops. Returns a summary suitable for the wizard's "done"
    /// screen.
    @MainActor
    static func apply(diffs: [ClipDiff], appState: AppState) -> ApplyResult {
        var result = ApplyResult()

        for d in diffs {
            guard let clip = d.clip else {
                if d.acceptedChangeCount >= 0 && d.unknown { /* not user-driven */ }
                result.unknownIdsSkipped += 1
                continue
            }

            let accepted = d.changes.filter(\.accepted)
            if accepted.isEmpty { continue }

            // 1) Field changes on the clip row.
            var mutated = clip
            var fieldChangeCount = 0
            for ch in accepted {
                switch ch.kind {
                case .title:
                    mutated.title = ch.newValue
                    fieldChangeCount += 1
                case .persona:
                    mutated.personaCode = ch.newValue
                    fieldChangeCount += 1
                case .description:
                    mutated.descriptionRaw = ch.newValue
                    fieldChangeCount += 1
                case .goLiveDate:
                    mutated.goLiveDate = ch.newValue.isEmpty ? nil : ch.newValue
                    fieldChangeCount += 1
                case .categoryAdd, .categoryRemove:
                    break
                }
            }

            var touched = false
            if fieldChangeCount > 0 {
                do {
                    try appState.updateClip(mutated)
                    result.fieldChangesApplied += fieldChangeCount
                    touched = true
                } catch {
                    result.errors.append("\(clip.id): \(error.localizedDescription)")
                    continue   // bail on this clip so we don't half-apply
                }
            }

            // 2) Category set replacement, but only if at least one
            //    category change was accepted. Build the resulting list by
            //    starting from the existing order, dropping accepted
            //    removals, and appending accepted additions in parse order.
            let acceptedAdds: [String] = accepted.compactMap { ch in
                if case .categoryAdd(let n) = ch.kind { return n }
                return nil
            }
            let acceptedRemoves: Set<String> = Set(accepted.compactMap { ch -> String? in
                if case .categoryRemove(let n) = ch.kind { return n.uppercased() }
                return nil
            })

            if !acceptedAdds.isEmpty || !acceptedRemoves.isEmpty {
                let kept = d.existingCategories.filter { !acceptedRemoves.contains($0.uppercased()) }
                let resolved: [Int64] = (kept + acceptedAdds).compactMap { name in
                    do {
                        let cat = try DatabaseService.shared.ensureCategory(named: name)
                        if !appState.categories.contains(where: { $0.id == cat.id }) {
                            result.categoriesCreated += 1
                        }
                        return cat.id
                    } catch {
                        result.errors.append("\(clip.id): category \(name) — \(error.localizedDescription)")
                        return nil
                    }
                }
                do {
                    try appState.setClipCategories(clipId: clip.id, categoryIds: resolved)
                    result.categoriesAdded   += acceptedAdds.count
                    result.categoriesRemoved += acceptedRemoves.count
                    touched = true
                } catch {
                    result.errors.append("\(clip.id): categories — \(error.localizedDescription)")
                }
            }

            if touched { result.clipsTouched += 1 }
        }

        appState.reloadAll()
        return result
    }
}
