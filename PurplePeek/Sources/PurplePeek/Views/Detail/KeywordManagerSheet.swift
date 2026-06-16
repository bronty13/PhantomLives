import SwiftUI

/// Global keyword manager: list every keyword with its in-use count, create new ones, and
/// delete unused ones. Deletion is blocked while a keyword is applied to any file (the
/// count is shown so the user knows why).
struct KeywordManagerSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.appTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var newName = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Keyword Manager").font(.title2.weight(.semibold))
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }

            HStack {
                TextField("New keyword", text: $newName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addNew)
                Button("Add", action: addNew)
                    .disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            HStack(spacing: 8) {
                Button {
                    appState.importKeywordsFromPhotos()
                } label: {
                    Label("Import from Photos", systemImage: "photo.on.rectangle.angled")
                }
                .disabled(appState.osxphotosPath == nil || appState.isImportingKeywords)
                if appState.isImportingKeywords {
                    ProgressView().controlSize(.small)
                }
                Spacer()
            }
            if appState.osxphotosPath == nil {
                Text("Install osxphotos (pipx install osxphotos) to pull keywords from your Photos library.")
                    .font(.caption2).foregroundStyle(.secondary)
            }

            Divider()

            if appState.keywords.isEmpty {
                Text("No keywords yet. Create one above, or add keywords from the detail panel.")
                    .font(.callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 1) {
                        ForEach(appState.keywords) { kw in
                            keywordRow(kw)
                        }
                    }
                }
            }
        }
        .padding(20)
        .frame(width: 420, height: 460)
    }

    private func keywordRow(_ kw: Keyword) -> some View {
        let count = appState.usageCount(forKeyword: kw.id)
        return HStack {
            Image(systemName: "tag").foregroundStyle(theme.accentColor)
            Text(kw.name)
            if kw.source == "photos" {
                Text("from Photos").font(.caption2).foregroundStyle(.secondary)
            }
            Spacer()
            Text(count == 0 ? "unused" : "\(count) file\(count == 1 ? "" : "s")")
                .font(.caption)
                .foregroundStyle(.secondary)
            Button {
                appState.deleteKeyword(kw.id)
            } label: {
                Image(systemName: "trash")
            }
            .buttonStyle(.plain)
            .foregroundStyle(count == 0 ? Color.red : Color.secondary.opacity(0.4))
            .disabled(count != 0)
            .help(count == 0 ? "Delete keyword" : "In use by \(count) file\(count == 1 ? "" : "s") — remove it from those first")
        }
        .padding(.vertical, 5)
        .padding(.horizontal, 6)
    }

    private func addNew() {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        appState.createKeyword(name: trimmed)
        newName = ""
    }
}
