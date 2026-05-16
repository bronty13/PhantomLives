import SwiftUI

/// Read-only horizontal strip of tag chips for a record. Renders the
/// effective tag set — per-record tags inside `fieldsJSON._tags`
/// merged with the type-scope tags on `ObjectType.tags`. Used by every
/// place that surfaces a record without opening Detail: list / kanban
/// / gallery / calendar rows on RecordsScreen, Today's timeline and
/// rails, and the Quick Switcher result row.
///
/// Chips use the tag's `colorHex`. Type-scope chips render with a
/// slightly lighter fill and a thin outline so users can tell at a
/// glance "this tag is inherited from the type, removing it requires
/// the schema editor" vs "this tag is on this record only." Editing
/// still lives in Detail (`TagPillRow`) and in the schema editor — the
/// strip is intentionally non-interactive to keep row hit-testing
/// simple.
struct RecordTagStrip: View {
    let record: ObjectRecord
    let type: ObjectType

    /// Display style. `.compact` clamps the strip to a single line and
    /// truncates the trailing chips with a "+N" overflow indicator —
    /// right for narrow card / calendar / quick-switcher contexts.
    /// `.wrap` lets chips flow onto a second line for places that have
    /// horizontal room (Detail hero, table row when used at full
    /// width).
    enum Style { case compact, wrap }

    var style: Style = .compact
    var maxCompactChips: Int = 3
    var font: Font = .caption2

    var body: some View {
        let tags = TagService.effectiveTags(for: record, in: type)
        let typeScopeIds = Set(type.tags)
        if !tags.isEmpty {
            switch style {
            case .compact:
                compactStrip(tags: tags, typeScopeIds: typeScopeIds)
            case .wrap:
                RecordTagFlow {
                    ForEach(tags, id: \.id) { tag in
                        chip(tag: tag, isTypeScope: typeScopeIds.contains(tag.id))
                    }
                }
            }
        }
    }

    private func compactStrip(tags: [TagDef], typeScopeIds: Set<String>) -> some View {
        let visible = Array(tags.prefix(maxCompactChips))
        let overflow = tags.count - visible.count
        return HStack(spacing: 4) {
            ForEach(visible, id: \.id) { tag in
                chip(tag: tag, isTypeScope: typeScopeIds.contains(tag.id))
            }
            if overflow > 0 {
                Text("+\(overflow)")
                    .font(font.weight(.medium))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func chip(tag: TagDef, isTypeScope: Bool) -> some View {
        let color = tag.colorHex.flatMap(Color.init(hex:)) ?? .secondary
        return Text(tag.name)
            .font(font.weight(.medium))
            .lineLimit(1)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(color.opacity(isTypeScope ? 0.14 : 0.22))
            .foregroundStyle(color)
            .overlay(
                Capsule()
                    .strokeBorder(color.opacity(isTypeScope ? 0.45 : 0.0),
                                  style: StrokeStyle(lineWidth: 0.6, dash: [2.5, 2]))
            )
            .clipShape(Capsule())
            .help(isTypeScope
                  ? "\(tag.name) · inherited from \(type.name) type"
                  : tag.name)
    }
}

/// Wrapping flow layout for the `.wrap` style. Mirrors the helpers in
/// `TagPillRow` and `SchemaEditor` — duplicated rather than shared so
/// the three call sites stay decoupled until a fourth appears.
private struct RecordTagFlow<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        RecordTagFlowLayout(spacing: 4) {
            content()
        }
    }
}

private struct RecordTagFlowLayout: Layout {
    var spacing: CGFloat = 4

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, maxRowWidth: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                maxRowWidth = max(maxRowWidth, x - spacing)
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
        maxRowWidth = max(maxRowWidth, x - spacing)
        return CGSize(width: maxRowWidth, height: y + lineHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x: CGFloat = bounds.minX, y: CGFloat = bounds.minY, lineHeight: CGFloat = 0
        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += lineHeight + spacing
                lineHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
        }
    }
}
