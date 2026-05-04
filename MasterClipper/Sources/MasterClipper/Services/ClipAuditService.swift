import Foundation

/// Validates a clip against the production-ready checklist:
///
///  1. Clip ID exists
///  2. Persona is identified
///  3. Title exists and looks plausible
///  4. Refined description exists
///  5. At least one category is selected
///  6. Content date is set
///  7. Go-Live date is set
///
/// Used by the per-clip audit banner in `ClipEditView` and the bulk audit
/// report in `Reports → Clip Audit`.
@MainActor
enum ClipAuditService {

    enum Issue: String, Hashable, CaseIterable, Identifiable {
        case missingId
        case missingPersona
        case missingTitle
        case suspiciousTitle
        case missingRefinedDescription
        case missingCategories
        case missingContentDate
        case missingGoLiveDate

        var id: String { rawValue }

        var label: String {
            switch self {
            case .missingId:                  return "Clip ID is missing"
            case .missingPersona:             return "Persona is not set"
            case .missingTitle:               return "Title is empty"
            case .suspiciousTitle:            return "Title looks like a placeholder (e.g. \"Untitled\", \"TBD\", or under 3 chars)"
            case .missingRefinedDescription:  return "Refined description is empty — paste raw transcription and click Refine via Ollama"
            case .missingCategories:          return "No categories selected"
            case .missingContentDate:         return "Content date is not set"
            case .missingGoLiveDate:          return "Go-Live date is not set"
            }
        }

        /// SF Symbol for the issue. Used by the banner / report row icons.
        var systemImage: String {
            switch self {
            case .missingId, .missingPersona:                 return "exclamationmark.octagon.fill"
            case .missingTitle, .suspiciousTitle:             return "textformat"
            case .missingRefinedDescription:                  return "wand.and.stars"
            case .missingCategories:                          return "tag"
            case .missingContentDate, .missingGoLiveDate:     return "calendar"
            }
        }
    }

    struct Result: Hashable {
        let clipId: String
        let title: String
        let personaCode: String
        let issues: [Issue]
        var ok: Bool { issues.isEmpty }
    }

    /// Audit a single clip. `categoryIds` lets the caller pass a live snapshot
    /// (used by the editor while edits are in flight); when nil the current
    /// committed `clip_categories` rows are loaded.
    static func audit(
        _ clip: Clip,
        categoryIds: [Int64]? = nil,
        appState: AppState
    ) -> Result {
        var issues: [Issue] = []

        if clip.id.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(.missingId)
        }
        if clip.personaCode.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(.missingPersona)
        } else if appState.persona(forCode: clip.personaCode) == nil {
            // Persona code on the clip doesn't resolve to a known persona.
            issues.append(.missingPersona)
        }

        let title = clip.title.trimmingCharacters(in: .whitespaces)
        if title.isEmpty {
            issues.append(.missingTitle)
        } else if isSuspiciousTitle(title) {
            issues.append(.suspiciousTitle)
        }

        if clip.descriptionRefined.trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(.missingRefinedDescription)
        }

        let cats: [Int64]
        if let categoryIds {
            cats = categoryIds
        } else {
            cats = (try? DatabaseService.shared.categoryIds(forClip: clip.id)) ?? []
        }
        if cats.isEmpty { issues.append(.missingCategories) }

        if (clip.contentDate ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(.missingContentDate)
        }
        if (clip.goLiveDate ?? "").trimmingCharacters(in: .whitespaces).isEmpty {
            issues.append(.missingGoLiveDate)
        }

        return Result(
            clipId: clip.id,
            title: clip.title,
            personaCode: clip.personaCode,
            issues: issues
        )
    }

    /// Audit every non-archived clip in `appState`. Sorted issues-first so
    /// the report defaults to "what needs attention".
    static func auditAll(appState: AppState) -> [Result] {
        appState.clips
            .filter { !$0.archived }
            .map { audit($0, appState: appState) }
            .sorted { lhs, rhs in
                if lhs.issues.count != rhs.issues.count {
                    return lhs.issues.count > rhs.issues.count
                }
                return lhs.clipId > rhs.clipId
            }
    }

    /// Heuristic: titles like "Untitled", "TBD", "test", or anything under
    /// 3 characters are flagged as suspect.
    private static func isSuspiciousTitle(_ title: String) -> Bool {
        let lower = title.lowercased().trimmingCharacters(in: .whitespaces)
        let placeholders: Set<String> = [
            "untitled", "tbd", "todo", "to-do", "to do",
            "test", "sample", "placeholder", "draft", "n/a", "na",
            "...", "…", "?", "x", "y",
        ]
        if placeholders.contains(lower) { return true }
        if lower.count < 3 { return true }
        return false
    }
}
