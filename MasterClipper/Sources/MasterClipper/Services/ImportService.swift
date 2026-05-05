import Foundation
import GRDB

/// Routes for the import wizard. Each maps a source sheet/table to a destination
/// in the database. Only `clips` is fully implemented in v1; the others are
/// best-effort backfills to seed reasonable starting state from the legacy xlsx.
enum ImportTarget: String, CaseIterable, Hashable {
    case clips
    case calendarEvents
    case clipPostings
    case prices
    case skip

    var label: String {
        switch self {
        case .clips:           return "Clips"
        case .calendarEvents:  return "Calendar Events"
        case .clipPostings:    return "Posting Backfill"
        case .prices:          return "Prices"
        case .skip:            return "Skip"
        }
    }
}

struct ImportSheetSpec: Identifiable, Hashable {
    var id: String { sheetName }
    let sheetName: String
    var rowCount: Int
    var columnCount: Int
    var target: ImportTarget
}

@MainActor
final class ImportService: ObservableObject {

    // MARK: - Source detection

    enum SourceKind { case xlsx, csv, tsv, text }

    static func detect(url: URL) -> SourceKind {
        switch url.pathExtension.lowercased() {
        case "xlsx", "xlsm": return .xlsx
        case "csv":          return .csv
        case "tsv":          return .tsv
        default:             return .text
        }
    }

    // MARK: - XLSX → routed sheets

    static func loadSheets(url: URL) throws -> [XLSXReader.Sheet] {
        try XLSXReader.read(url: url)
    }

    /// Auto-routes each sheet to a sensible default `ImportTarget` based on its name.
    /// Order of checks matters — narrower patterns first. If no sheet matches
    /// any pattern (e.g., a single sheet named "Sheet1"), the largest sheet is
    /// promoted to Clips so the wizard always has at least one default target.
    static func suggestRouting(for sheets: [XLSXReader.Sheet]) -> [ImportSheetSpec] {
        var specs: [ImportSheetSpec] = sheets.map { sheet in
            let lower = sheet.name.lowercased()
            let target: ImportTarget
            if lower.contains("scheduler") {
                target = .calendarEvents
            } else if lower.contains("price") {
                target = .prices
            } else if lower.contains("post") && !lower.contains("clip") {
                target = .clipPostings
            } else if lower.contains("clip") {
                target = .clips
            } else if lower.contains("data") {
                target = .clips
            } else {
                target = .skip
            }
            return ImportSheetSpec(
                sheetName: sheet.name,
                rowCount: sheet.rows.count,
                columnCount: sheet.rows.map(\.count).max() ?? 0,
                target: target
            )
        }

        // Fallback: if name-based routing produced no Clips target (single-sheet
        // workbook, generic "Sheet1" name, etc.), promote the row-count winner.
        if !specs.contains(where: { $0.target == .clips }) {
            if let i = specs.indices.max(by: { specs[$0].rowCount < specs[$1].rowCount }) {
                specs[i].target = .clips
            }
        }

        return specs
    }

    // MARK: - Header detection

    /// Picks the most plausible header row among the first 15 rows: the one
    /// with the most non-empty text-ish cells (≥ 50% non-numeric), preferring
    /// later rows on ties (so a row of merged-section titles above the real
    /// header — like "Curse Of Curves (CoC)" — doesn't win over the actual
    /// column-name row beneath it).
    static func extractHeader(from rows: [[String]]) -> (headerRowIndex: Int, headers: [String], dataRows: [[String]]) {
        let scanLimit = min(rows.count, 15)
        var best: (idx: Int, score: Int) = (-1, 0)
        for idx in 0..<scanLimit {
            let row = rows[idx]
            let nonEmpty = row.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            if nonEmpty.count < 2 { continue }
            let texty = nonEmpty.filter { Double($0) == nil }.count
            // Require at least half the populated cells to be non-numeric (a
            // header is mostly words, a data row is mostly numbers/dates).
            if texty * 2 < nonEmpty.count { continue }
            // ≥ vs > so that ties prefer later rows — handles the merged-title
            // pattern where a real header sits below a sparse section banner.
            if nonEmpty.count >= best.score {
                best = (idx, nonEmpty.count)
            }
        }
        if best.idx >= 0 {
            return (best.idx, rows[best.idx], Array(rows.dropFirst(best.idx + 1)))
        }
        if let first = rows.first {
            return (0, first, Array(rows.dropFirst()))
        }
        return (0, [], [])
    }

    // MARK: - CSV / TSV / pasted text

    static func parseDelimited(text: String, separator: Character) -> [[String]] {
        var rows: [[String]] = []
        var current: [String] = []
        var field = ""
        var inQuotes = false
        var iter = text.makeIterator()
        while let ch = iter.next() {
            if inQuotes {
                if ch == "\"" {
                    inQuotes = false
                } else {
                    field.append(ch)
                }
            } else if ch == "\"" {
                inQuotes = true
            } else if ch == separator {
                current.append(field)
                field = ""
            } else if ch == "\n" {
                current.append(field)
                rows.append(current)
                current = []
                field = ""
            } else if ch == "\r" {
                continue
            } else {
                field.append(ch)
            }
        }
        if !field.isEmpty || !current.isEmpty {
            current.append(field)
            rows.append(current)
        }
        return rows
    }

    static func detectDelimiter(text: String) -> Character {
        let firstLine = text.split(separator: "\n").first.map(String.init) ?? ""
        if firstLine.contains("\t") { return "\t" }
        if firstLine.contains(",")  { return "," }
        return ","
    }

    // MARK: - Commit clips

    struct ClipsCommitResult {
        var inserted: Int
        var skippedDuplicates: Int
        var failed: Int
        var historicalMarked: Int
        var errors: [String]
    }

    static func commitClips(
        rows: [[String]],
        mapping: [Int: ClipFieldKey],
        appState: AppState,
        duplicateStrategy: String,
        markAllAsHistorical: Bool = false
    ) -> ClipsCommitResult {
        var result = ClipsCommitResult(inserted: 0, skippedDuplicates: 0, failed: 0,
                                       historicalMarked: 0, errors: [])

        // Pre-fetch existing clips for duplicate detection
        let existingClips = (try? DatabaseService.shared.fetchAllClips(includeArchived: true)) ?? []
        var byExternalId: [String: Clip] = [:]
        var byTitleDate: [String: Clip] = [:]
        for c in existingClips {
            if let ext = c.externalClipId, !ext.isEmpty {
                byExternalId[ext] = c
            }
            let key = "\(c.title.lowercased())|\(c.contentDate ?? "")"
            byTitleDate[key] = c
        }

        // Pre-fetch categories for ensure-style lookup
        var categoryByName: [String: Int64] = [:]
        for c in (try? DatabaseService.shared.fetchCategories(includeArchived: true)) ?? [] {
            if let id = c.id { categoryByName[c.name.lowercased()] = id }
        }

        for (rowIndex, row) in rows.enumerated() {
            let parsed = parseRow(row, mapping: mapping)
            // Skip empty rows
            if parsed.title.isEmpty && (parsed.descriptionRaw ?? "").isEmpty
                && (parsed.externalClipId ?? "").isEmpty {
                continue
            }

            // Duplicate check
            var existing: Clip? = nil
            if let ext = parsed.externalClipId, !ext.isEmpty, let dup = byExternalId[ext] {
                existing = dup
            } else {
                let key = "\(parsed.title.lowercased())|\(parsed.contentDate ?? "")"
                if let dup = byTitleDate[key] { existing = dup }
            }
            if existing != nil && duplicateStrategy == "skip" {
                result.skippedDuplicates += 1
                continue
            }

            // Build clip
            do {
                let id: String
                if let existing { id = existing.id }
                else {
                    let dateForId = parseDate(parsed.contentDate)
                    id = try IDGeneratorService.next(forContentDate: dateForId)
                }

                let now = DatabaseService.isoNow()
                let clip = Clip(
                    id: id,
                    externalClipId: parsed.externalClipId,
                    trackingTag: parsed.trackingTag,
                    personaCode: parsed.personaCode ?? appState.settings.defaultPersonaCode,
                    title: parsed.title,
                    descriptionRaw: parsed.descriptionRaw ?? "",
                    descriptionRefined: parsed.descriptionRefined ?? existing?.descriptionRefined ?? "",
                    keywords: parsed.keywords ?? "",
                    performers: parsed.performers ?? "",
                    clipFilename: parsed.clipFilename,
                    thumbnailFilename: parsed.thumbnailFilename,
                    previewFilename: parsed.previewFilename,
                    lengthSeconds: parsed.lengthSeconds,
                    priceCents: parsed.priceCents,
                    salesCount: parsed.salesCount ?? 0,
                    incomeCents: parsed.incomeCents ?? 0,
                    contentDate: parsed.contentDate,
                    goLiveDate: parsed.goLiveDate,
                    status: mapStatus(parsed.status),
                    archived: false,
                    notes: parsed.notes ?? "",
                    transcript: existing?.transcript ?? "",
                    mp4Md5:    existing?.mp4Md5    ?? "",
                    mp4Sha1:   existing?.mp4Sha1   ?? "",
                    mp4Sha256: existing?.mp4Sha256 ?? "",
                    mp4SizeBytes: existing?.mp4SizeBytes,
                    reducedMd5:    existing?.reducedMd5    ?? "",
                    reducedSha1:   existing?.reducedSha1   ?? "",
                    reducedSha256: existing?.reducedSha256 ?? "",
                    reducedSizeBytes: existing?.reducedSizeBytes,
                    hashesComputedAt: existing?.hashesComputedAt ?? "",
                    postingExcluded: existing?.postingExcluded ?? false,
                    exclusionReason: existing?.exclusionReason ?? "",
                    exclusionNotes:  existing?.exclusionNotes  ?? "",
                    createdAt: existing?.createdAt ?? now,
                    updatedAt: now
                )

                if existing != nil {
                    try DatabaseService.shared.updateClip(clip)
                } else {
                    try DatabaseService.shared.insertClip(clip)
                }

                if markAllAsHistorical {
                    if let n = try? DatabaseService.shared.markAllScopedSitesPosted(
                        clipId: id,
                        postedDate: nil,
                        notes: "Imported as historical"
                    ), n > 0 {
                        result.historicalMarked += 1
                    }
                }

                // Ensure & link categories
                if !parsed.categoryNames.isEmpty {
                    var ids: [Int64] = []
                    for name in parsed.categoryNames {
                        let lname = name.lowercased()
                        if let cid = categoryByName[lname] {
                            ids.append(cid)
                        } else {
                            let cat = try DatabaseService.shared.ensureCategory(named: name)
                            if let cid = cat.id {
                                categoryByName[lname] = cid
                                ids.append(cid)
                            }
                        }
                    }
                    try DatabaseService.shared.setCategories(forClip: id, categoryIds: ids)
                }

                result.inserted += 1
            } catch {
                result.failed += 1
                result.errors.append("Row \(rowIndex + 1): \(error.localizedDescription)")
            }
        }

        appState.reloadClips()
        appState.reloadCategories()
        return result
    }

    // MARK: - Commit calendar events

    struct CalendarCommitResult {
        var inserted: Int
        var updated: Int
        var skipped: Int
        var failed: Int
    }

    /// Backfills calendar_events from a sheet shaped like {Date, Day, Persona, Title, Notes, ...}.
    /// Looks for a column resolving to "date" and "persona", best-effort title and notes.
    static func commitCalendarEvents(
        rows: [[String]],
        mapping: [Int: ClipFieldKey],
        sourceColumns: [String],
        appState: AppState
    ) -> CalendarCommitResult {
        var result = CalendarCommitResult(inserted: 0, updated: 0, skipped: 0, failed: 0)

        // Find the column indexes by looking at the column headers (mapping isn't enough here
        // since Calendar Events have only loosely matching ClipFieldKeys — content date / notes).
        let dateCol     = sourceColumns.firstIndex(where: { FuzzyMatch.normalize($0).contains("date") }) ?? -1
        let personaCol  = sourceColumns.firstIndex(where: { FuzzyMatch.normalize($0).contains("persona") }) ?? -1
        let titleCol    = sourceColumns.firstIndex(where: {
            let n = FuzzyMatch.normalize($0)
            return n.contains("title") || n.contains("topic") || n.contains("content")
        }) ?? -1
        let notesCol    = sourceColumns.firstIndex(where: { FuzzyMatch.normalize($0).contains("note") }) ?? -1

        guard dateCol >= 0 && personaCol >= 0 else {
            return result
        }

        let now = DatabaseService.isoNow()
        for row in rows {
            guard row.count > max(dateCol, personaCol) else { result.skipped += 1; continue }
            let dateRaw = row[dateCol]
            let persona = row[personaCol].trimmingCharacters(in: .whitespaces)
            guard !persona.isEmpty,
                  let date = parseDate(dateRaw)
            else {
                result.skipped += 1
                continue
            }
            let dateStr = DatabaseService.isoDate(date)
            let title  = (titleCol >= 0 && titleCol < row.count) ? row[titleCol] : ""
            let notes  = (notesCol >= 0 && notesCol < row.count) ? row[notesCol] : ""

            do {
                try DatabaseService.shared.dbPool.write { db in
                    if var existing = try CalendarEvent
                        .filter(Column("date") == dateStr && Column("persona_code") == persona)
                        .fetchOne(db)
                    {
                        existing.title = title
                        existing.notes = notes
                        existing.updatedAt = now
                        try existing.update(db)
                        result.updated += 1
                    } else {
                        var event = CalendarEvent(
                            id: nil, date: dateStr, personaCode: persona,
                            clipId: nil, title: title, notes: notes,
                            createdAt: now, updatedAt: now
                        )
                        try event.insert(db)
                        result.inserted += 1
                    }
                }
            } catch {
                result.failed += 1
            }
        }
        return result
    }

    // MARK: - Date / row parsing

    private struct ParsedClipFields {
        var externalClipId: String?
        var trackingTag: String?
        var personaCode: String?
        var title: String = ""
        var descriptionRaw: String?
        var descriptionRefined: String?
        var keywords: String?
        var performers: String?
        var clipFilename: String?
        var thumbnailFilename: String?
        var previewFilename: String?
        var lengthSeconds: Int?
        var priceCents: Int?
        var salesCount: Int?
        var incomeCents: Int?
        var contentDate: String?
        var goLiveDate: String?
        var status: String?
        var notes: String?
        var categoryNames: [String] = []
    }

    /// Clean a free-form / voice-transcribed categories cell into a discrete
    /// list. Real cells look like:
    ///   `cat shoes , flats , bbw`
    ///   `categories chastity , mindfuck , tease and denial`
    ///   `So, the categories are homewrecking, cheating, slut training`
    ///   `Categories: edging. denial. tease.`
    ///
    /// Strategy: repeatedly strip any leading filler words ("so", "uh"…),
    /// punctuation, and explicit "categories"-type prefixes. Split on `,` (the
    /// dominant separator across this user's data), trim per item, drop trailing
    /// periods and empty/single-char fragments. " and " is intentionally NOT
    /// treated as a separator because real categories like "tease and denial"
    /// contain it; the user can split those manually if needed.
    static func parseCategories(_ raw: String) -> [String] {
        var s = raw.trimmingCharacters(in: .whitespaces)
        // Iteratively peel off prefix garbage until nothing more to strip.
        var passes = 0
        while passes < 8 {
            let before = s
            s = stripLeadingPunct(s)
            s = stripLeadingFiller(s)
            s = stripLeadingPunct(s)
            s = stripLeadingCategoriesPrefix(s)
            s = stripLeadingPunct(s)
            if s == before { break }
            passes += 1
        }
        return s.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { stripTrailingPunct($0) }
            .map { $0.replacingOccurrences(of: "  ", with: " ") }
            .filter { !$0.isEmpty && $0.count > 1 }
    }

    private static let categoryFillerWords: Set<String> = [
        "so", "uh", "um", "ok", "okay", "well", "alright"
    ]

    /// Listed longest-first so the longer phrase wins the prefix race.
    private static let categoryPrefixes: [String] = [
        "the categories are",
        "the category are",
        "categories are",
        "category list",
        "the categories",
        "the category",
        "categories",
        "category",
        "tags are",
        "the tags are",
        "tags",
        "cat",
    ]

    private static func stripLeadingFiller(_ s: String) -> String {
        let lower = s.lowercased()
        for word in categoryFillerWords {
            if lower.hasPrefix(word + " ")
                || lower.hasPrefix(word + ",")
                || lower.hasPrefix(word + ".")
            {
                return String(s.dropFirst(word.count))
            }
        }
        return s
    }

    private static func stripLeadingCategoriesPrefix(_ s: String) -> String {
        let lower = s.lowercased()
        for p in categoryPrefixes {
            if lower.hasPrefix(p + " ")
                || lower.hasPrefix(p + ",")
                || lower.hasPrefix(p + ":")
                || lower == p
            {
                return String(s.dropFirst(p.count))
            }
        }
        return s
    }

    private static func stripLeadingPunct(_ s: String) -> String {
        var out = s
        let punct: Set<Character> = [",", ".", ";", ":", "-", "—", "!", "?"]
        while let first = out.first, punct.contains(first) || first.isWhitespace {
            out.removeFirst()
        }
        return out
    }

    private static func stripTrailingPunct(_ s: String) -> String {
        var out = s
        let punct: Set<Character> = [".", ";", ":", "!", "?", ","]
        while let last = out.last, punct.contains(last) || last.isWhitespace {
            out.removeLast()
        }
        return out
    }

    /// Map various persona spellings to canonical codes. Most spreadsheets
    /// have inconsistent casing (`COC`, `CoC`, `coc`). The DB side is
    /// `COLLATE NOCASE` so this is mostly cosmetic, but keeps the clip rows
    /// uniform.
    static func canonicalPersona(_ raw: String) -> String {
        let upper = raw.uppercased().trimmingCharacters(in: .whitespaces)
        switch upper {
        case "COC":             return "CoC"
        case "POA":             return "PoA"
        case "SHR", "SHEER":    return "Shr"
        case "N/A", "NA":       return "N/A"
        default:                return raw.trimmingCharacters(in: .whitespaces)
        }
    }

    private static func parseRow(_ row: [String], mapping: [Int: ClipFieldKey]) -> ParsedClipFields {
        var fields = ParsedClipFields()
        for (idx, key) in mapping {
            guard idx < row.count else { continue }
            let value = row[idx].trimmingCharacters(in: .whitespaces)
            if value.isEmpty { continue }
            switch key {
            case .ignore:               break
            case .externalClipId:       fields.externalClipId = value
            case .trackingTag:          fields.trackingTag    = value
            case .personaCode:          fields.personaCode    = canonicalPersona(value)
            case .title:                fields.title          = value
            case .descriptionRaw:       fields.descriptionRaw = value
            case .descriptionRefined:   fields.descriptionRefined = value
            case .keywords:             fields.keywords       = value
            case .performers:           fields.performers     = value
            case .clipFilename:         fields.clipFilename   = value
            case .thumbnailFilename:    fields.thumbnailFilename = value
            case .previewFilename:      fields.previewFilename   = value
            case .lengthSeconds:        fields.lengthSeconds  = parseLength(value)
            case .priceCents:           fields.priceCents     = parsePriceCents(value)
            case .salesCount:           fields.salesCount     = Int(value)
            case .incomeCents:          fields.incomeCents    = parsePriceCents(value)
            case .contentDate:          fields.contentDate    = parseDateISO(value)
            case .goLiveDate:           fields.goLiveDate     = parseDateISO(value)
            case .status:               fields.status         = value
            case .notes:                fields.notes          = value
            case .categories:
                fields.categoryNames = parseCategories(value)
            }
        }
        return fields
    }

    private static func parseLength(_ s: String) -> Int? {
        if let secs = DurationFormatter.parse(s) { return secs }
        // Excel stores durations sometimes as fractional days
        if let d = Double(s) {
            // Heuristic: if 0 < d < 1, treat as fraction of a day
            if d > 0 && d < 1 {
                return Int((d * 86400).rounded())
            }
            // Else assume seconds
            return Int(d)
        }
        // Try compact "7m49s" or "7:49"
        let trimmed = s.replacingOccurrences(of: "m", with: ":")
            .replacingOccurrences(of: "s", with: "")
            .replacingOccurrences(of: " ", with: "")
        if !trimmed.isEmpty, let secs = DurationFormatter.parse(trimmed) {
            return secs
        }
        return nil
    }

    private static func parsePriceCents(_ s: String) -> Int? {
        let cleaned = s.replacingOccurrences(of: "$", with: "")
                       .replacingOccurrences(of: ",", with: "")
                       .trimmingCharacters(in: .whitespaces)
        if cleaned.isEmpty { return nil }
        guard let v = Double(cleaned) else { return nil }
        return Int((v * 100).rounded())
    }

    private static func parseDate(_ raw: String?) -> Date? {
        guard let raw, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)

        // Excel date serial number?
        if let serial = Double(trimmed), serial > 1 && serial < 100000 {
            // Excel epoch is 1899-12-30 (leap-year bug for Mac convention)
            let epoch = DateComponents(year: 1899, month: 12, day: 30)
            if let base = Calendar(identifier: .gregorian).date(from: epoch) {
                return base.addingTimeInterval(serial * 86400)
            }
        }

        let formats = [
            "yyyy-MM-dd",
            "yyyy-MM-dd'T'HH:mm:ss",
            "yyyy-MM-dd HH:mm:ss",
            "MM/dd/yyyy",
            "M/d/yyyy",
            "yyyy/MM/dd",
            "MMM d, yyyy",
            "MMMM d, yyyy",
        ]
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        for f in formats {
            fmt.dateFormat = f
            if let d = fmt.date(from: trimmed) { return d }
        }
        return nil
    }

    private static func parseDateISO(_ s: String) -> String? {
        guard let d = parseDate(s) else { return nil }
        return DatabaseService.isoDate(d)
    }

    /// Map a free-form import status string to the new pipeline. The auto-
    /// status logic in `DatabaseService` will overwrite this immediately on
    /// insert based on real data; this is just a sensible seed.
    private static func mapStatus(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return ClipStatus.new.rawValue }
        let l = raw.lowercased().trimmingCharacters(in: .whitespaces)
        switch l {
        case "active", "ready", "live", "to post", "to_post":
            return ClipStatus.toPost.rawValue
        case "delivered", "posted", "done":
            return ClipStatus.production.rawValue
        case "post-production", "postprod", "editing", "p7_under_review":
            return ClipStatus.editing.rawValue
        case "posting":
            return ClipStatus.posting.rawValue
        case "production":
            return ClipStatus.production.rawValue
        case "new", "draft", "pending", "under_review", "archived":
            return ClipStatus.new.rawValue
        default:
            if let s = ClipStatus(rawValue: l) { return s.rawValue }
            return ClipStatus.new.rawValue
        }
    }
}
