import SwiftUI

/// Read-only field renderers shared by the four list views (table /
/// kanban / calendar / gallery) and the detail header. Edit-mode
/// renderers live in `Detail.swift`. Marked `@MainActor` because the
/// `.link` branch resolves linked record titles via `ObjectEngine`,
/// which is itself main-actor isolated.
@MainActor
enum FieldDisplay {

    @ViewBuilder
    static func cell(field: FieldDef, value: Any?, isPrimary: Bool = false) -> some View {
        let raw = stringValue(value)
        switch field.kind {
        case .text, .longText, .url, .email:
            if raw.isEmpty {
                if isPrimary {
                    Text("Untitled").italic().foregroundStyle(.tertiary).lineLimit(1)
                } else {
                    Text("—").foregroundStyle(.tertiary)
                }
            } else {
                Text(raw).lineLimit(1)
            }
        case .richText:
            // List/table cells render the plain mirror, not RTF — the
            // full WYSIWYG only appears in the detail editor.
            let plain: String = {
                if let dict = value as? [String: Any] {
                    return (dict["plain"] as? String) ?? ""
                }
                return raw
            }()
            if plain.isEmpty {
                Text("—").foregroundStyle(.tertiary)
            } else {
                Text(plain).lineLimit(2)
            }
        case .noteLog:
            // Cell summary: "N entries · last: <plain preview>"
            let dict = value as? [String: Any]
            let entries = (dict?["entries"] as? [[String: Any]]) ?? []
            if entries.isEmpty {
                Text("—").foregroundStyle(.tertiary)
            } else {
                let count = entries.count
                let latestPlain = entries
                    .max(by: { (l, r) in
                        ((l["createdAt"] as? String) ?? "") < ((r["createdAt"] as? String) ?? "")
                    })
                    .flatMap { $0["plain"] as? String } ?? ""
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(count) \(count == 1 ? "entry" : "entries")")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.secondary)
                    if !latestPlain.isEmpty {
                        Text(latestPlain)
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                            .lineLimit(1)
                    }
                }
            }
        case .number:
            if let s = numberValueOrNil(value) {
                Text(s).monospacedDigit()
            } else {
                Text("—").foregroundStyle(.tertiary)
            }
        case .date, .dateTime:
            if let s = dateValueOrNil(value, includeTime: field.kind == .dateTime) {
                Text(s).foregroundStyle(.secondary)
            } else {
                Text("—").foregroundStyle(.tertiary)
            }
        case .boolean:
            Image(systemName: (value as? Bool) == true ? "checkmark.square.fill" : "square")
                .foregroundStyle((value as? Bool) == true ? Color.green : .secondary)
        case .select:
            selectChip(value: value, options: field.options)
        case .multiSelect:
            multiSelectChips(value: value, options: field.options)
        case .link:
            if raw.isEmpty {
                Text("—").foregroundStyle(.tertiary)
            } else if let title = ObjectEngine.resolveLinkedTitle(recordId: raw) {
                // Resolved id → linked record's title.
                HStack(spacing: 4) {
                    Image(systemName: "link")
                        .foregroundStyle(.tint).imageScale(.small)
                    Text(title).foregroundStyle(.tint).lineLimit(1)
                }
            } else {
                // Unresolvable id (legacy free-text or deleted record).
                Text(raw).foregroundStyle(.tint).italic().lineLimit(1)
            }
        case .rating:
            ratingView(value: value)
        case .attachment:
            if raw.isEmpty {
                Text("—").foregroundStyle(.tertiary)
            } else {
                Image(systemName: "paperclip").foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    static func selectChip(value: Any?, options: [FieldOption]) -> some View {
        let label = stringValue(value)
        let opt = options.first { $0.name == label }
        let chipColor: Color = opt?.colorHex.flatMap(Color.init(hex:)) ?? .secondary
        if !label.isEmpty {
            Text(label)
                .font(.caption.weight(.medium))
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(chipColor.opacity(0.2))
                .foregroundStyle(chipColor)
                .clipShape(Capsule())
        } else {
            Text("—").foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    static func multiSelectChips(value: Any?, options: [FieldOption]) -> some View {
        let labels = (value as? [String]) ?? []
        HStack(spacing: 4) {
            ForEach(labels, id: \.self) { label in
                let opt = options.first { $0.name == label }
                let chipColor: Color = opt?.colorHex.flatMap(Color.init(hex:)) ?? .secondary
                Text(label)
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(chipColor.opacity(0.2))
                    .foregroundStyle(chipColor)
                    .clipShape(Capsule())
            }
        }
    }

    static func ratingView(value: Any?) -> some View {
        let stars = (value as? Int) ?? Int((value as? Double) ?? 0)
        return HStack(spacing: 1) {
            ForEach(0..<5, id: \.self) { i in
                Image(systemName: i < stars ? "star.fill" : "star")
                    .foregroundStyle(i < stars ? Color.yellow : .secondary)
                    .imageScale(.small)
            }
        }
    }

    // MARK: - Value helpers

    static func stringValue(_ v: Any?) -> String {
        if let s = v as? String, !s.isEmpty { return s }
        return ""
    }

    static func numberValueOrNil(_ v: Any?) -> String? {
        if let d = v as? Double { return d.formatted() }
        if let i = v as? Int    { return "\(i)" }
        return nil
    }

    static func dateValueOrNil(_ v: Any?, includeTime: Bool) -> String? {
        guard let s = v as? String, !s.isEmpty,
              let date = ISO8601DateFormatter().date(from: s) else { return nil }
        return date.formatted(date: .abbreviated, time: includeTime ? .shortened : .omitted)
    }

    static func parsedDate(_ v: Any?) -> Date? {
        guard let s = v as? String, !s.isEmpty,
              let date = ISO8601DateFormatter().date(from: s) else { return nil }
        return date
    }

    /// The display title for a record — its primary field value if present,
    /// otherwise "Untitled". Branches on the field's `kind` so non-text
    /// primaries (notably Weight's numeric `pounds` and any date-keyed
    /// type) render as the formatted value rather than falling through
    /// to "Untitled" because an `as? String` cast fails on a `Double`.
    static func title(of record: ObjectRecord, in type: ObjectType) -> String {
        guard let key = type.primaryFieldKey else { return "Untitled" }
        let raw = record.fields()[key]
        if let field = type.field(forKey: key) {
            switch field.kind {
            case .number:
                if let s = numberValueOrNil(raw) { return s }
            case .date, .dateTime:
                if let s = dateValueOrNil(raw, includeTime: field.kind == .dateTime) { return s }
            default:
                break
            }
        }
        if let s = raw as? String, !s.isEmpty { return s }
        return "Untitled"
    }
}
