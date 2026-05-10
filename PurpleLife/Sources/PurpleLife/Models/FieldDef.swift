import Foundation

/// A single field on an object type. Owned by `ObjectType`. Stored as part
/// of the type definition (in `schema.json`), not on every record. The
/// values for each field live inside `ObjectRecord.fieldsJSON`, keyed by
/// `FieldDef.key`.
struct FieldDef: Codable, Identifiable, Hashable {
    var id: String              // stable UUID; never reused after delete
    var key: String             // storage key inside fields_json (snake_case)
    var name: String            // display label
    var kind: FieldKind
    var options: [FieldOption]  // populated for `.select` / `.multiSelect`
    var required: Bool
    var description: String?

    /// Convenience constructor — generates an id, derives the key from the
    /// name if you don't pass one explicitly.
    static func make(
        name: String,
        kind: FieldKind,
        key: String? = nil,
        options: [FieldOption] = [],
        required: Bool = false,
        description: String? = nil
    ) -> FieldDef {
        FieldDef(
            id: UUID().uuidString,
            key: key ?? slugify(name),
            name: name,
            kind: kind,
            options: options,
            required: required,
            description: description
        )
    }

    private static func slugify(_ s: String) -> String {
        let lowered = s.lowercased()
        var out = ""
        var lastWasSep = true
        for c in lowered {
            if c.isLetter || c.isNumber {
                out.append(c)
                lastWasSep = false
            } else if !lastWasSep {
                out.append("_")
                lastWasSep = true
            }
        }
        if out.hasSuffix("_") { out.removeLast() }
        return out.isEmpty ? "field" : out
    }
}

enum FieldKind: String, Codable, CaseIterable, Hashable {
    case text          // single-line string
    case longText      // multi-line / markdown
    case number        // double
    case date          // calendar day, no time component
    case dateTime      // moment in time
    case boolean       // yes/no
    case select        // single choice from `options`
    case multiSelect   // many choices from `options`
    case link          // relation to another ObjectRecord (by id)
    case rating        // 0–5 stars
    case url
    case email
    case attachment    // sha256 ref into the attachments table

    var displayName: String {
        switch self {
        case .text:        return "Text"
        case .longText:    return "Long text"
        case .number:      return "Number"
        case .date:        return "Date"
        case .dateTime:    return "Date & time"
        case .boolean:     return "Yes / no"
        case .select:      return "Select"
        case .multiSelect: return "Multi-select"
        case .link:        return "Link to object"
        case .rating:      return "Rating"
        case .url:         return "URL"
        case .email:       return "Email"
        case .attachment:  return "Attachment"
        }
    }

    /// SF Symbol shown in the type/field editor and field-type picker.
    var systemImage: String {
        switch self {
        case .text:        return "text.alignleft"
        case .longText:    return "text.justify"
        case .number:      return "number"
        case .date:        return "calendar"
        case .dateTime:    return "calendar.badge.clock"
        case .boolean:     return "checkmark.square"
        case .select:      return "chevron.down.circle"
        case .multiSelect: return "list.bullet"
        case .link:        return "link"
        case .rating:      return "star"
        case .url:         return "link.circle"
        case .email:       return "envelope"
        case .attachment:  return "paperclip"
        }
    }

    /// Whether this field can drive a kanban grouping. Only enums make
    /// sensible group columns.
    var canGroupForKanban: Bool { self == .select }

    /// Whether this field can drive a calendar view.
    var canDateForCalendar: Bool { self == .date || self == .dateTime }

    /// Whether the link/attachment kinds reference other things by id.
    var isReference: Bool { self == .link || self == .attachment }
}

/// One option on a `.select` or `.multiSelect` field.
struct FieldOption: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var colorHex: String?

    static func make(_ name: String, colorHex: String? = nil) -> FieldOption {
        FieldOption(id: UUID().uuidString, name: name, colorHex: colorHex)
    }
}
