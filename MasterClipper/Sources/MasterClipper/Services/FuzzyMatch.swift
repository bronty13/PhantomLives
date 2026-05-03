import Foundation

enum FuzzyMatch {

    /// Aliases (lowercase, normalized) that map source column names → target field.
    /// All entries should be pre-normalized — pass them through `normalize` when
    /// adding (it strips punctuation / parens and lowercases).
    static let aliases: [ClipFieldKey: [String]] = [
        .externalClipId:    ["clip id", "id", "#", "external id", "clipid"],
        .trackingTag:       ["clip tracking tag", "tracking tag", "tag"],
        .personaCode:       ["persona", "model", "brand"],
        .title:             ["title", "title new", "new title", "clip title", "name"],
        .descriptionRaw:    ["description", "description raw", "description transcribe",
                             "raw description", "desc", "clip description",
                             "summary", "transcript", "transcription"],
        .descriptionRefined:["description refined", "description corrected",
                             "refined description", "corrected description",
                             "refined", "corrected"],
        .categories:        ["categories", "category", "tags"],
        .keywords:          ["keywords", "keyword"],
        .clipFilename:      ["clip filename", "filename", "file"],
        .thumbnailFilename: ["clip thumbnail filename", "thumbnail filename", "thumbnail", "thumb"],
        .previewFilename:   ["clip preview filename", "preview filename", "preview"],
        .performers:        ["performers", "performer", "talent", "models", "cast"],
        .lengthSeconds:     ["length", "duration", "runtime"],
        .priceCents:        ["price", "cost", "usd", "list price"],
        .salesCount:        ["sales", "sales #", "sold", "units"],
        .incomeCents:       ["income", "revenue", "total", "income 6mo creator s share"],
        .contentDate:       ["content date", "recorded", "shoot date", "session", "date recorded"],
        .goLiveDate:        ["go live", "go live date", "release", "posted",
                             "release date", "live date", "publish date"],
        .status:            ["status", "clip status", "state"],
        .notes:             ["notes", "note", "schedule notes"],
    ]

    /// Suggest a target field for the given source column header. nil = no good match.
    static func suggest(column: String) -> ClipFieldKey? {
        let normalized = normalize(column)
        guard !normalized.isEmpty else { return nil }

        // Exact alias match first
        for (key, list) in aliases {
            if list.contains(normalized) { return key }
        }

        // Fuzzy fallback — pick best similarity, threshold 0.78
        var best: (key: ClipFieldKey, score: Double)? = nil
        for (key, list) in aliases {
            for alias in list {
                let s = similarity(normalized, alias)
                if s > 0.78 && (best == nil || s > best!.score) {
                    best = (key, s)
                }
            }
        }
        return best?.key
    }

    static func normalize(_ s: String) -> String {
        var x = s.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        let punct = ["_", "-", ".", ",", "?", "!", ":", ";", "(", ")", "[", "]", "/", "'"]
        for p in punct { x = x.replacingOccurrences(of: p, with: " ") }
        while x.contains("  ") { x = x.replacingOccurrences(of: "  ", with: " ") }
        return x.trimmingCharacters(in: .whitespaces)
    }

    static func similarity(_ a: String, _ b: String) -> Double {
        if a == b { return 1 }
        if a.isEmpty || b.isEmpty { return 0 }
        let dist = levenshtein(a, b)
        let maxLen = max(a.count, b.count)
        return 1 - Double(dist) / Double(maxLen)
    }

    static func levenshtein(_ a: String, _ b: String) -> Int {
        let aChars = Array(a)
        let bChars = Array(b)
        let n = aChars.count
        let m = bChars.count
        if n == 0 { return m }
        if m == 0 { return n }
        var prev = Array(0...m)
        var curr = Array(repeating: 0, count: m + 1)
        for i in 1...n {
            curr[0] = i
            for j in 1...m {
                let cost = aChars[i - 1] == bChars[j - 1] ? 0 : 1
                curr[j] = min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost)
            }
            swap(&prev, &curr)
        }
        return prev[m]
    }
}
