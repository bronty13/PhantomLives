import SwiftUI

/// Ordered category chip picker. Categories are bound as an ordered array
/// because every posting platform respects the creator's category order; the
/// position is persisted in `clip_categories.position`.
///
/// Reorder by drag-and-drop: drag any chip onto another to insert it before
/// that chip's position. The `×` removes a chip; the menu picks an existing
/// but unselected category; the inline TextField creates a new category on
/// Return.
struct CategoryChipPicker: View {
    @EnvironmentObject private var appState: AppState
    @Binding var selectedIds: [Int64]

    @State private var inlineNewName: String = ""
    @FocusState private var inlineFocused: Bool
    @State private var error: String?
    @State private var dragTargetId: Int64?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !selectedIds.isEmpty {
                Text("Categories — drag to reorder. Order matters: every posting site respects it.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            FlowLayout(spacing: 6) {
                ForEach(Array(selectedIds.enumerated()), id: \.element) { (idx, id) in
                    if let cat = appState.categories.first(where: { $0.id == id }) {
                        draggableChip(category: cat, index: idx)
                    }
                }

                Menu {
                    let available = appState.categories
                        .filter { !$0.archived }
                        .filter { c in
                            guard let cid = c.id else { return false }
                            return !selectedIds.contains(cid)
                        }
                    if available.isEmpty {
                        Text("No more existing categories — type below to create one")
                    } else {
                        ForEach(available) { cat in
                            Button(cat.name) {
                                if let cid = cat.id, !selectedIds.contains(cid) {
                                    selectedIds.append(cid)
                                }
                            }
                        }
                    }
                } label: {
                    Label("Pick existing", systemImage: "plus.circle.fill")
                        .labelStyle(.titleAndIcon)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.quaternary, in: Capsule())
                }
                .menuStyle(.borderlessButton)
                .fixedSize()
            }

            // Inline "create new category" — type a name and hit Return.
            HStack(spacing: 8) {
                Image(systemName: "plus.circle")
                    .foregroundStyle(.secondary)
                TextField("Create new category — type and press Return", text: $inlineNewName)
                    .textFieldStyle(.roundedBorder)
                    .focused($inlineFocused)
                    .onSubmit { createInline() }
                    .frame(maxWidth: 360)
                if !inlineNewName.trimmingCharacters(in: .whitespaces).isEmpty {
                    Button("Add", action: createInline)
                        .keyboardShortcut(.defaultAction)
                }
                if let err = error {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
        }
    }

    // MARK: - Chip view (draggable + drop target)

    @ViewBuilder
    private func draggableChip(category cat: Category, index: Int) -> some View {
        if let cid = cat.id {
            let isDropTarget = dragTargetId == cid
            HStack(spacing: 4) {
                Image(systemName: "line.3.horizontal")
                    .font(.caption2).foregroundStyle(.secondary)
                Text("\(index + 1).")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                Text(cat.name)
                Button {
                    selectedIds.removeAll { $0 == cid }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .imageScale(.small)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(.tertiary, in: Capsule())
            .overlay(
                Capsule()
                    .stroke(isDropTarget ? Color.accentColor : .clear, lineWidth: 2)
            )
            .draggable("\(cid)") {
                Text(cat.name)
                    .padding(.horizontal, 10).padding(.vertical, 5)
                    .background(.regularMaterial, in: Capsule())
                    .shadow(radius: 4)
            }
            .dropDestination(for: String.self) { items, _ in
                handleDrop(items: items, before: cid)
            } isTargeted: { active in
                if active { dragTargetId = cid }
                else if dragTargetId == cid { dragTargetId = nil }
            }
        }
    }

    /// Move the dropped category id to the position currently held by the
    /// target id. Returns true on success, false on no-op.
    private func handleDrop(items: [String], before targetId: Int64) -> Bool {
        guard let droppedIdStr = items.first,
              let droppedId = Int64(droppedIdStr),
              droppedId != targetId,
              let fromIdx = selectedIds.firstIndex(of: droppedId),
              let toIdx   = selectedIds.firstIndex(of: targetId)
        else { return false }
        selectedIds.remove(at: fromIdx)
        // If we removed an earlier index, the target index shifted down by 1.
        let insertAt = fromIdx < toIdx ? toIdx - 1 : toIdx
        selectedIds.insert(droppedId, at: insertAt)
        dragTargetId = nil
        return true
    }

    // MARK: - Inline create

    /// Create-or-attach: if a category with the typed name (case-insensitive)
    /// already exists, append it; otherwise create a new one and append it.
    /// Cleared and re-focused on success so the user can rapid-fire tags.
    private func createInline() {
        let raw = inlineNewName.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        do {
            if let existing = appState.categories.first(where: { $0.name.caseInsensitiveCompare(raw) == .orderedSame }),
               let id = existing.id {
                if !selectedIds.contains(id) { selectedIds.append(id) }
            } else {
                let cat = try DatabaseService.shared.ensureCategory(named: raw)
                if let id = cat.id, !selectedIds.contains(id) {
                    selectedIds.append(id)
                }
                appState.reloadCategories()
            }
            inlineNewName = ""
            error = nil
            inlineFocused = true
        } catch {
            self.error = error.localizedDescription
        }
    }
}

/// Simple wrapping HStack — wraps children to the next row when they overflow.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let layout = layoutLines(subviews: subviews, maxWidth: width)
        return CGSize(width: layout.width, height: layout.height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let layout = layoutLines(subviews: subviews, maxWidth: bounds.width)
        for placement in layout.placements {
            placement.subview.place(
                at: CGPoint(x: bounds.minX + placement.origin.x, y: bounds.minY + placement.origin.y),
                proposal: ProposedViewSize(placement.size)
            )
        }
    }

    private struct Placement {
        let subview: LayoutSubview
        let origin: CGPoint
        let size: CGSize
    }

    private func layoutLines(subviews: Subviews, maxWidth: CGFloat) -> (placements: [Placement], width: CGFloat, height: CGFloat) {
        var placements: [Placement] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var lineHeight: CGFloat = 0
        var totalWidth: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += lineHeight + spacing
                lineHeight = 0
            }
            placements.append(Placement(subview: subview, origin: CGPoint(x: x, y: y), size: size))
            x += size.width + spacing
            lineHeight = max(lineHeight, size.height)
            totalWidth = max(totalWidth, x - spacing)
        }
        return (placements, totalWidth, y + lineHeight)
    }
}
