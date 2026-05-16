import SwiftUI

/// Cross-cutting tag pill row, embedded at the bottom of the Detail
/// main pane. Reads & writes `fieldsBuffer[TagDef.recordKey]` (the
/// reserved `_tags` array of tag ids); the parent Detail view persists
/// the change on Done through `ObjectEngine.update`, which fans the
/// edit through FTS, sync, undo, and the `record_tags` index.
///
/// The picker is presented as a popover anchored on the "Add tag"
/// button so it slots into the existing Detail layout without
/// claiming sheet real estate.
struct TagPillRow: View {
    @Binding var tagIds: [String]
    @State private var showPicker = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: "tag")
                    .foregroundStyle(.tertiary)
                    .imageScale(.small)
                Text("Tags")
                    .font(.caption.weight(.semibold))
                    .textCase(.uppercase).tracking(0.5)
                    .foregroundStyle(.secondary)
            }
            FlowChips {
                ForEach(resolvedTags, id: \.id) { tag in
                    pill(tag: tag)
                }
                addButton
            }
        }
    }

    // MARK: - Pills

    private var resolvedTags: [TagDef] {
        // Resolve through the vocabulary and preserve the on-record
        // order so a user-curated sequence of tags doesn't reshuffle
        // alphabetically on every render.
        let vocab = Dictionary(uniqueKeysWithValues: TagService.allTags.map { ($0.id, $0) })
        return tagIds.compactMap { vocab[$0] }
    }

    private func pill(tag: TagDef) -> some View {
        let color = tag.colorHex.flatMap(Color.init(hex:)) ?? .secondary
        return HStack(spacing: 4) {
            Text(tag.name)
                .font(.caption.weight(.medium))
            Button {
                tagIds.removeAll { $0 == tag.id }
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.small)
                    .foregroundStyle(color.opacity(0.6))
            }
            .buttonStyle(.plain)
            .help("Remove \(tag.name)")
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(color.opacity(0.20))
        .foregroundStyle(color)
        .clipShape(Capsule())
    }

    private var addButton: some View {
        Button {
            showPicker = true
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "plus")
                    .imageScale(.small)
                Text("Add tag")
                    .font(.caption.weight(.medium))
            }
            .padding(.horizontal, 8).padding(.vertical, 3)
            .background(Color.secondary.opacity(0.08))
            .foregroundStyle(.secondary)
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .popover(isPresented: $showPicker, arrowEdge: .bottom) {
            TagChipPicker(selectedTagIds: Set(tagIds)) { picked in
                if !tagIds.contains(picked) {
                    tagIds.append(picked)
                }
                showPicker = false
            }
        }
    }
}

/// Wrap-on-overflow row for tag chips. Detail.swift's existing
/// `WrappingHStack` / `FlowLayout` is fileprivate; redeclaring the
/// 30-line `Layout` here keeps the views decoupled.
private struct FlowChips<Content: View>: View {
    @ViewBuilder let content: () -> Content

    var body: some View {
        FlowLayout(spacing: 6) {
            content()
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

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
