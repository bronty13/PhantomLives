import SwiftUI

struct CategoryChipPicker: View {
    @EnvironmentObject private var appState: AppState
    @Binding var selectedIds: Set<Int64>

    @State private var inlineNewName: String = ""
    @FocusState private var inlineFocused: Bool
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            FlowLayout(spacing: 6) {
                ForEach(Array(selectedIds), id: \.self) { id in
                    if let cat = appState.categories.first(where: { $0.id == id }) {
                        chip(label: cat.name) {
                            selectedIds.remove(id)
                        }
                    }
                }

                Menu {
                    let available = appState.categories
                        .filter { !$0.archived }
                        .filter { id in
                            guard let cid = id.id else { return false }
                            return !selectedIds.contains(cid)
                        }
                    if available.isEmpty {
                        Text("No more existing categories — type below to create one")
                    } else {
                        ForEach(available) { cat in
                            Button(cat.name) {
                                if let cid = cat.id { selectedIds.insert(cid) }
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

    /// Create-or-attach: if a category with the typed name (case-insensitive)
    /// already exists, select it; otherwise create a new one and select it.
    /// Cleared and re-focused on success so the user can rapid-fire tags.
    private func createInline() {
        let raw = inlineNewName.trimmingCharacters(in: .whitespaces)
        guard !raw.isEmpty else { return }
        do {
            // Reuse existing category if one matches by name (case-insensitive)
            if let existing = appState.categories.first(where: { $0.name.caseInsensitiveCompare(raw) == .orderedSame }),
               let id = existing.id {
                selectedIds.insert(id)
            } else {
                let cat = try DatabaseService.shared.ensureCategory(named: raw)
                if let id = cat.id { selectedIds.insert(id) }
                appState.reloadCategories()
            }
            inlineNewName = ""
            error = nil
            inlineFocused = true
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func chip(label: String, onRemove: @escaping () -> Void) -> some View {
        HStack(spacing: 4) {
            Text(label)
            Button(action: onRemove) {
                Image(systemName: "xmark.circle.fill")
                    .imageScale(.small)
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(.tertiary, in: Capsule())
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
