import SwiftUI

struct TagsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var newTagName: String = ""
    @State private var newTagColor: Color = .blue
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                TextField("New tag name", text: $newTagName)
                    .textFieldStyle(.roundedBorder)
                    .frame(maxWidth: 240)
                ColorPicker("", selection: $newTagColor, supportsOpacity: false)
                    .labelsHidden()
                Button("Add") { addTag() }
                    .disabled(newTagName.trimmingCharacters(in: .whitespaces).isEmpty)
                Spacer()
                if let err = error {
                    Text(err).font(.caption).foregroundStyle(.red)
                }
            }
            .padding(.horizontal, 16).padding(.vertical, 10)

            Divider()

            if appState.tags.isEmpty {
                Spacer()
                Text("No tags yet — add one above.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                Spacer()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 280), spacing: 10)],
                               spacing: 10) {
                        ForEach(appState.tags) { tag in
                            TagRow(tag: tag) { delete in
                                if let id = tag.rowId, delete {
                                    try? appState.deleteTag(id: id)
                                }
                            }
                        }
                    }
                    .padding(16)
                }
            }
        }
        .navigationTitle("Tags")
    }

    private func addTag() {
        let name = newTagName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        if appState.tags.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) {
            error = "A tag with that name already exists."
            return
        }
        do {
            try appState.saveTag(Tag(rowId: nil, name: name, colorHex: newTagColor.toHex() ?? "#888888"))
            newTagName = ""
            error = nil
        } catch {
            self.error = error.localizedDescription
        }
    }
}

private struct TagRow: View {
    @EnvironmentObject private var appState: AppState
    let tag: Tag
    let onDelete: (Bool) -> Void

    @State private var color: Color = .gray

    var body: some View {
        HStack(spacing: 12) {
            ColorPicker("", selection: $color, supportsOpacity: false)
                .labelsHidden()
                .onChange(of: color) { _, new in
                    var t = tag
                    t.colorHex = new.toHex() ?? t.colorHex
                    try? appState.saveTag(t)
                }
            TagChip(tag: tag)
            Spacer()
            Text("\(usageCount) events")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button(role: .destructive) { onDelete(true) } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(.background.opacity(0.6)))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(.secondary.opacity(0.2), lineWidth: 0.5))
        .onAppear {
            color = Color(hex: tag.colorHex) ?? .gray
        }
    }

    private var usageCount: Int {
        // Cheap O(events × tags-per-event) — fine at MVP scale.
        appState.tagsByEvent.values.reduce(0) { acc, list in
            acc + (list.contains(where: { $0.rowId == tag.rowId }) ? 1 : 0)
        }
    }
}
