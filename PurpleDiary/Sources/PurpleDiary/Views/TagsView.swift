import SwiftUI

/// Manage tags: add a named+colored tag, recolor, or delete. Deleting a tag
/// cascades its entry links (FK ON DELETE CASCADE) but leaves the entries.
struct TagsView: View {
    @EnvironmentObject private var appState: AppState
    @State private var newName: String = ""
    @State private var newColor: Color = .purple

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            addRow
            Divider()
            if appState.tags.isEmpty {
                emptyState
            } else {
                List {
                    ForEach(appState.tags) { tag in
                        TagRow(tag: tag)
                    }
                }
                .listStyle(.inset)
            }
        }
    }

    private var addRow: some View {
        HStack {
            ColorPicker("", selection: $newColor, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 36)
            TextField("Add a tag…", text: $newName, prompt: Text("Add a tag…"))
                .textFieldStyle(.plain)
                .onSubmit(add)
            Button("Add", action: add)
                .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
        .padding(10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "tag")
                .font(.system(size: 32)).foregroundStyle(.secondary)
            Text("No tags yet. Tags help you filter and find entries later.")
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        let hex = newColor.toHex() ?? "#888888"
        try? appState.saveTag(Tag(rowId: nil, name: name, colorHex: hex))
        newName = ""
    }
}

private struct TagRow: View {
    @EnvironmentObject private var appState: AppState
    let tag: Tag
    @State private var color: Color = .gray
    @State private var loaded = false

    var body: some View {
        HStack {
            ColorPicker("", selection: $color, supportsOpacity: false)
                .labelsHidden()
                .frame(width: 36)
                .onChange(of: color) { _, newValue in
                    guard loaded else { return }
                    var t = tag
                    t.colorHex = newValue.toHex() ?? tag.colorHex
                    try? appState.saveTag(t)
                }
            Text(tag.name)
            Spacer()
            Button(role: .destructive) {
                if let rid = tag.rowId { try? appState.deleteTag(id: rid) }
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
        }
        .onAppear {
            color = Color(hex: tag.colorHex) ?? .gray
            loaded = true
        }
    }
}
