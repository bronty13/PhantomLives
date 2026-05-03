import Foundation

/// A virtual posting target = a (site, persona) combination. Clips4Sale × CoC
/// and Clips4Sale × PoA are run as separate posting batches because each has
/// its own login / posting flow.
struct PostingTarget: Identifiable, Hashable {
    let site: Site
    let personaCode: String

    var id: String { "\(site.id ?? -1)-\(personaCode)" }

    var label: String {
        "\(site.displayName) [\(personaCode)]"
    }
}

@MainActor
enum PostingTargets {
    /// Expand the configured (site, personaScope) into individual (site, persona)
    /// targets, in the order the user expects to run them: site sort_order asc,
    /// then persona sort_order asc.
    static func expanded(appState: AppState) -> [PostingTarget] {
        var out: [PostingTarget] = []
        let activeSites = appState.sites.filter { !$0.archived }
            .sorted { $0.sortOrder < $1.sortOrder }
        let personasByCode = Dictionary(uniqueKeysWithValues:
            appState.personas.map { ($0.code, $0) })
        for site in activeSites {
            for code in site.personaScopeList {
                let personaSortOrder = personasByCode[code]?.sortOrder ?? 999
                let target = PostingTarget(site: site, personaCode: code)
                let item = (target, personaSortOrder)
                if let insertAt = out.firstIndex(where: {
                    let other = personasByCode[$0.personaCode]?.sortOrder ?? 999
                    return $0.site.id == site.id && other > personaSortOrder
                }) {
                    out.insert(item.0, at: insertAt)
                } else {
                    out.append(item.0)
                }
            }
        }
        return out
    }
}
