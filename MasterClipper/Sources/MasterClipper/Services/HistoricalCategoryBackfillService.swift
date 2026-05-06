import Foundation

/// Plans + executes a one-shot backfill: for every clip in `production`
/// status with no categories assigned, look up a matching row in
/// `c4s_historical` and propose its `categories + keywords` (in that
/// order, deduped, uppercased) as the new category list. Matching is
/// title-only because the legacy `external_clip_id` column is just an
/// import sequence number, not the C4S clip ID.
///
/// The service is **read-only** — it returns a `Plan` the UI can show
/// the user. Actual writes happen via
/// `DatabaseService.applyHistoricalCategoryBackfill(_:)`.
enum HistoricalCategoryBackfillService {

    enum MatchKind: String {
        case exact   // titles match after FuzzyMatch.normalize
        case strong  // similarity >= 0.92
        case maybe   // 0.75 <= similarity < 0.92
    }

    /// One row in the proposed plan — a clip + the C4S row we'd take
    /// categories from + the categories themselves. The UI renders one
    /// of these per checkbox row and passes the user-checked subset
    /// back to the commit method.
    struct Candidate: Identifiable, Hashable {
        let clipId: String
        let clipTitle: String
        let personaCode: String
        let c4sClipId: String
        let c4sTitle: String
        let c4sStore: String
        let categories: [String]    // ordered, deduped, uppercased
        let kind: MatchKind
        let score: Double
        var storeMismatch: Bool { c4sStore != personaCode }

        var id: String { clipId }
    }

    /// A clip we can't confidently match — surfaced in the sheet with
    /// the best near-miss (if any) so the user knows what we tried.
    struct UnmatchedClip: Identifiable, Hashable {
        let clipId: String
        let clipTitle: String
        let personaCode: String
        let bestCandidateTitle: String?
        let bestCandidateStore: String?
        let bestScore: Double

        var id: String { clipId }
    }

    struct Plan {
        let exact: [Candidate]
        let strong: [Candidate]    // 0.92 <= score < 1.0
        let maybe: [Candidate]     // 0.75 <= score < 0.92
        let unmatched: [UnmatchedClip]

        var totalTargetClips: Int {
            exact.count + strong.count + maybe.count + unmatched.count
        }
    }

    /// Threshold layers, mirrored in the sheet's section headers.
    static let strongThreshold: Double = 0.92
    static let maybeThreshold:  Double = 0.75

    /// Build the plan. Pure read; never writes.
    @MainActor
    static func plan() throws -> Plan {
        // 1. Targets: production status, zero clip_categories rows.
        let targets = try DatabaseService.shared.fetchProductionClipsWithoutCategories()
        // 2. Pool: every C4S historical row, regardless of store. We'll
        //    score within-store first, then cross-store as fallback.
        let pool = try DatabaseService.shared.fetchC4SHistorical()

        guard !targets.isEmpty, !pool.isEmpty else {
            return Plan(exact: [], strong: [], maybe: [], unmatched: [])
        }

        // Pre-compute normalized titles once.
        struct PoolEntry {
            let row: C4SHistoricalRecord
            let norm: String
        }
        let poolEntries = pool.map {
            PoolEntry(row: $0, norm: FuzzyMatch.normalize($0.title))
        }

        var exact: [Candidate] = []
        var strong: [Candidate] = []
        var maybe: [Candidate] = []
        var unmatched: [UnmatchedClip] = []

        for clip in targets {
            let normClip = FuzzyMatch.normalize(clip.title)
            if normClip.isEmpty {
                unmatched.append(UnmatchedClip(
                    clipId: clip.id, clipTitle: clip.title,
                    personaCode: clip.personaCode,
                    bestCandidateTitle: nil, bestCandidateStore: nil,
                    bestScore: 0
                ))
                continue
            }

            // Prefer same-store. The 1 known cross-store collision in
            // the user's data is a duplicate title — taking the
            // wrong-store row is worse than leaving it unmatched.
            let sameStore = poolEntries.filter { $0.row.store == clip.personaCode }
            let scopedPool = sameStore.isEmpty ? poolEntries : sameStore

            // Exact (post-normalize) wins outright.
            if let hit = scopedPool.first(where: { $0.norm == normClip }) {
                exact.append(buildCandidate(clip: clip, row: hit.row,
                                            kind: .exact, score: 1.0))
                continue
            }

            // Best fuzzy within scoped pool.
            var best: (entry: PoolEntry, score: Double)? = nil
            for entry in scopedPool {
                let s = FuzzyMatch.similarity(normClip, entry.norm)
                if best == nil || s > best!.score {
                    best = (entry, s)
                }
            }

            guard let best = best else {
                unmatched.append(UnmatchedClip(
                    clipId: clip.id, clipTitle: clip.title,
                    personaCode: clip.personaCode,
                    bestCandidateTitle: nil, bestCandidateStore: nil,
                    bestScore: 0
                ))
                continue
            }

            if best.score >= strongThreshold {
                strong.append(buildCandidate(clip: clip, row: best.entry.row,
                                             kind: .strong, score: best.score))
            } else if best.score >= maybeThreshold {
                maybe.append(buildCandidate(clip: clip, row: best.entry.row,
                                            kind: .maybe, score: best.score))
            } else {
                unmatched.append(UnmatchedClip(
                    clipId: clip.id, clipTitle: clip.title,
                    personaCode: clip.personaCode,
                    bestCandidateTitle: best.entry.row.title,
                    bestCandidateStore: best.entry.row.store,
                    bestScore: best.score
                ))
            }
        }

        // Sort each bucket alphabetically by clip title for stable display.
        let byTitle: (Candidate, Candidate) -> Bool = {
            $0.clipTitle.localizedCaseInsensitiveCompare($1.clipTitle) == .orderedAscending
        }
        return Plan(
            exact:  exact.sorted(by: byTitle),
            strong: strong.sorted(by: byTitle),
            maybe:  maybe.sorted(by: byTitle),
            unmatched: unmatched.sorted {
                $0.clipTitle.localizedCaseInsensitiveCompare($1.clipTitle) == .orderedAscending
            }
        )
    }

    private static func buildCandidate(
        clip: Clip,
        row: C4SHistoricalRecord,
        kind: MatchKind,
        score: Double
    ) -> Candidate {
        Candidate(
            clipId: clip.id,
            clipTitle: clip.title,
            personaCode: clip.personaCode,
            c4sClipId: row.clipId,
            c4sTitle: row.title,
            c4sStore: row.store,
            categories: combineCategoriesAndKeywords(row: row),
            kind: kind,
            score: score
        )
    }

    /// `categories + keywords` in that order, split on `,`, uppercased
    /// + trimmed, deduped by first occurrence (preserves order).
    /// Matches the user's spec — Categories first, Keywords second,
    /// order matters.
    static func combineCategoriesAndKeywords(row: C4SHistoricalRecord) -> [String] {
        let parts = (row.categories + "," + row.keywords)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
        var seen = Set<String>()
        var out: [String] = []
        for p in parts where !seen.contains(p) {
            seen.insert(p)
            out.append(p)
        }
        return out
    }
}
