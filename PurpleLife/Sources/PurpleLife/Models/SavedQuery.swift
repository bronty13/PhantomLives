import Foundation

/// A serializable filter spec for the Today view's panels.
///
/// Phase 3 starts deliberately narrow: a query is "records of optional
/// type T where field K equals V (or has a non-empty value), sorted by
/// field S, limited to N rows". That's enough to express "currently
/// reading", "recent X", "today's photo shoots", and a generic "latest
/// across everything" without any hard-coded view code.
///
/// More expressive predicates (date ranges, multi-clause filters,
/// computed fields) come in later Phase 3 work — extending this struct
/// in place is fine because the JSON shape is forgiving (Codable's
/// missing-key tolerance keeps older saved queries readable).
struct SavedQuery: Codable, Identifiable, Hashable {
    var id: String                  // stable UUID
    var name: String                // display label, e.g. "Currently reading"
    var systemImage: String         // SF Symbol shown in the panel header
    var typeId: String?             // nil = across every type
    var filterFieldKey: String?     // nil = no field filter
    var filterValue: FilterValue?   // requires filterFieldKey when set
    var sortFieldKey: String?       // nil → updated_at
    var descending: Bool
    var limit: Int                  // 0 = unlimited (rendered as 100 in UI)
    var builtIn: Bool               // user can hide but not delete

    enum FilterValue: Codable, Hashable {
        case string(String)
        case bool(Bool)
        case withinDays(Int)        // updated_at >= now - N days
        case nonEmpty               // any non-null, non-empty value

        enum CodingKeys: String, CodingKey { case kind, value }

        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            switch try c.decode(String.self, forKey: .kind) {
            case "string":     self = .string(try c.decode(String.self, forKey: .value))
            case "bool":       self = .bool(try c.decode(Bool.self, forKey: .value))
            case "withinDays": self = .withinDays(try c.decode(Int.self, forKey: .value))
            case "nonEmpty":   self = .nonEmpty
            default:           self = .nonEmpty
            }
        }

        func encode(to encoder: Encoder) throws {
            var c = encoder.container(keyedBy: CodingKeys.self)
            switch self {
            case .string(let s):     try c.encode("string", forKey: .kind);     try c.encode(s, forKey: .value)
            case .bool(let b):       try c.encode("bool", forKey: .kind);       try c.encode(b, forKey: .value)
            case .withinDays(let d): try c.encode("withinDays", forKey: .kind); try c.encode(d, forKey: .value)
            case .nonEmpty:          try c.encode("nonEmpty", forKey: .kind)
            }
        }
    }

    static func make(
        name: String,
        systemImage: String,
        typeId: String? = nil,
        filterFieldKey: String? = nil,
        filterValue: FilterValue? = nil,
        sortFieldKey: String? = nil,
        descending: Bool = true,
        limit: Int = 5,
        builtIn: Bool = false
    ) -> SavedQuery {
        SavedQuery(
            id: UUID().uuidString,
            name: name,
            systemImage: systemImage,
            typeId: typeId,
            filterFieldKey: filterFieldKey,
            filterValue: filterValue,
            sortFieldKey: sortFieldKey,
            descending: descending,
            limit: limit,
            builtIn: builtIn
        )
    }
}

/// Built-in seed queries installed on first launch. They're just default
/// values — once persisted, the user can edit names / filters / sorts in
/// the (forthcoming) Today customization UI.
enum SavedQuerySeed {
    static let allDefaults: [SavedQuery] = [
        // The plan calls out these three explicitly in the Phase 3
        // acceptance gate ("planner items + current weight +
        // currently-reading book"). They sit at the top of Today.
        SavedQuery(
            id: "default.todays-planner",
            name: "Today's planner",
            systemImage: "calendar.day.timeline.left",
            typeId: "PlannerItem",
            filterFieldKey: "status",
            filterValue: .string("Pending"),
            sortFieldKey: "date",
            descending: false,
            limit: 8,
            builtIn: true
        ),
        SavedQuery(
            id: "default.latest-weight",
            name: "Latest weight",
            systemImage: "scalemass",
            typeId: "Weight",
            filterFieldKey: nil,
            filterValue: nil,
            sortFieldKey: "date",
            descending: true,
            limit: 1,
            builtIn: true
        ),
        SavedQuery(
            id: "default.currently-reading",
            name: "Currently reading",
            systemImage: "book.closed",
            typeId: "Book",
            filterFieldKey: "status",
            filterValue: .string("Reading"),
            sortFieldKey: nil,
            descending: true,
            limit: 5,
            builtIn: true
        ),
        SavedQuery(
            id: "default.recent-people",
            name: "Recent people",
            systemImage: "person.2",
            typeId: "Person",
            filterFieldKey: nil,
            filterValue: nil,
            sortFieldKey: nil,
            descending: true,
            limit: 5,
            builtIn: true
        ),
        SavedQuery(
            id: "default.this-week",
            name: "Updated in the last 7 days",
            systemImage: "sparkles",
            typeId: nil,
            filterFieldKey: nil,
            filterValue: .withinDays(7),
            sortFieldKey: nil,
            descending: true,
            limit: 10,
            builtIn: true
        )
    ]
}
