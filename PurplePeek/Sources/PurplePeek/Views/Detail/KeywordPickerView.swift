import SwiftUI

/// Popover for choosing keywords on the selected file. Lists all keywords with a checkmark
/// for the ones applied; tapping toggles membership (persisted immediately). A field at the
/// bottom creates a new keyword and applies it.
struct KeywordPickerView: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.appTheme) private var theme
    @State private var search = ""
    @State private var newName = ""

    private var filtered: [Keyword] {
        let all = appState.keywords
        guard !search.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Keywords").font(.headline)

            TextField("Search…", text: $search)
                .textFieldStyle(.roundedBorder)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 1) {
                    ForEach(filtered) { kw in
                        Button {
                            appState.toggleKeyword(kw.id)
                        } label: {
                            HStack {
                                Image(systemName: appState.selectedKeywordIds.contains(kw.id) ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(appState.selectedKeywordIds.contains(kw.id) ? theme.accentColor : .secondary)
                                Text(kw.name)
                                if kw.source == "photos" {
                                    Image(systemName: "photo").font(.caption2).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .contentShape(Rectangle())
                            .padding(.vertical, 3)
                            .padding(.horizontal, 4)
                        }
                        .buttonStyle(.plain)
                    }
                    if filtered.isEmpty {
                        Text("No matching keywords").font(.caption).foregroundStyle(.secondary).padding(6)
                    }
                }
            }
            .frame(height: 220)

            Divider()

            HStack {
                TextField("New keyword", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addNew)
                Button("Add", action: addNew)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(14)
        .frame(width: 280)
    }

    private func addNew() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        if let kw = appState.createKeyword(name: trimmed) {
            if !appState.selectedKeywordIds.contains(kw.id) { appState.toggleKeyword(kw.id) }
        }
        newName = ""
    }
}
