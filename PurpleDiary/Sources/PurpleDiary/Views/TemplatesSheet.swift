import SwiftUI

/// Manage entry templates: a master list on the left, an editor on the right.
/// Templates are reusable scaffolds; their `{{date}}`, `{{time}}`, `{{weekday}}`,
/// `{{date_long}}`, `{{year}}` tokens are filled in when you start an entry from
/// one. Reached from the New Entry split-menu → "Manage Templates…".
struct TemplatesSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var selectedId: String?
    @State private var draftName: String = ""
    @State private var draftBody: String = ""
    @State private var showingLibrary = false

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                list.frame(width: 220)
                Divider()
                editor.frame(maxWidth: .infinity)
            }
            Divider()
            HStack {
                Text("Tokens: {{date}} · {{date_long}} · {{time}} · {{weekday}} · {{year}}")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { saveDraft(); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 720, height: 480)
        .onAppear { if selectedId == nil { selectFirstOrNothing() } }
        .sheet(isPresented: $showingLibrary) {
            TemplateLibrarySheet { added in
                // Select the most recently added one so the user lands on it.
                if let last = added.last { selectedId = last.id; loadDraft() }
            }
            .environmentObject(appState)
        }
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Text("Templates").font(.headline)
                Spacer()
                Button { saveDraft(); showingLibrary = true } label: {
                    Image(systemName: "books.vertical")
                }
                .buttonStyle(.borderless)
                .help("Add from the built-in template library")
                Button { addTemplate() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("New blank template")
            }
            .padding(10)
            Divider()
            List(selection: $selectedId) {
                ForEach(appState.templates) { t in
                    Text(t.name.isEmpty ? "Untitled" : t.name).tag(Optional(t.id))
                }
            }
            .onChange(of: selectedId) { old, _ in saveDraft(for: old); loadDraft() }
        }
    }

    @ViewBuilder
    private var editor: some View {
        if selectedId != nil {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Name", text: $draftName)
                    .textFieldStyle(.roundedBorder)
                    .font(.headline)
                Text("Body").font(.caption).foregroundStyle(.secondary)
                TextEditor(text: $draftBody)
                    .font(.body.monospaced())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.secondary.opacity(0.25)))
                Button(role: .destructive) { deleteSelected() } label: {
                    Label("Delete Template", systemImage: "trash")
                }
                .buttonStyle(.borderless)
            }
            .padding(12)
        } else {
            VStack(spacing: 8) {
                Image(systemName: "doc.text").font(.system(size: 34)).foregroundStyle(.secondary)
                Text("Select or create a template.").foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Actions

    private func selectFirstOrNothing() {
        selectedId = appState.templates.first?.id
        loadDraft()
    }

    private func loadDraft() {
        guard let id = selectedId, let t = appState.templates.first(where: { $0.id == id }) else {
            draftName = ""; draftBody = ""; return
        }
        draftName = t.name; draftBody = t.body
    }

    private func saveDraft(for id: String? = nil) {
        let targetId = id ?? selectedId
        guard let targetId, var t = appState.templates.first(where: { $0.id == targetId }) else { return }
        guard t.name != draftName || t.body != draftBody else { return }
        t.name = draftName; t.body = draftBody
        try? appState.updateTemplate(t)
    }

    private func addTemplate() {
        saveDraft()
        do {
            let t = try appState.createTemplate(name: "New Template", body: "")
            selectedId = t.id
            loadDraft()
        } catch { appState.errorMessage = error.localizedDescription }
    }

    private func deleteSelected() {
        guard let id = selectedId else { return }
        try? appState.deleteTemplate(id: id)
        selectFirstOrNothing()
    }
}

/// The built-in template library: a scrollable list of curated scaffolds the
/// user can add to their own templates with one click. Available to *every*
/// install — unlike the first-run seed, which only fires on an empty table — so
/// existing journals can pull in templates added in later versions. A curated
/// item already present (matched by name) shows "Added" instead of an Add button.
/// Calls `onAdded` with the templates created so the caller can select one.
struct TemplateLibrarySheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// Reports the templates created during this session (in add order).
    let onAdded: ([Template]) -> Void

    @State private var added: [Template] = []

    private var existingNames: Set<String> {
        Set(appState.templates.map { $0.name.trimmingCharacters(in: .whitespaces) })
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Template Library").font(.headline)
                    Text("\(TemplateLibrary.all.count) ready-made scaffolds — add any you like, then edit freely.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(12)
            Divider()

            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(TemplateLibrary.all) { curated in
                        row(curated)
                        Divider()
                    }
                }
            }

            Divider()
            HStack {
                Text(added.isEmpty ? "Nothing added yet."
                                   : "Added \(added.count) template\(added.count == 1 ? "" : "s").")
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Done") { onAdded(added); dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding(12)
        }
        .frame(width: 560, height: 520)
    }

    @ViewBuilder
    private func row(_ curated: CuratedTemplate) -> some View {
        let alreadyAdded = existingNames.contains(curated.name)
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "doc.text")
                .foregroundStyle(appState.effectiveAccentColor)
                .frame(width: 20)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 3) {
                Text(curated.name).font(.subheadline.weight(.medium))
                Text(curated.blurb).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if alreadyAdded {
                Label("Added", systemImage: "checkmark")
                    .font(.caption).foregroundStyle(.secondary)
                    .labelStyle(.titleAndIcon)
            } else {
                Button("Add") { add(curated) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .contentShape(Rectangle())
    }

    private func add(_ curated: CuratedTemplate) {
        do {
            let t = try appState.createTemplate(name: curated.name, body: curated.body)
            added.append(t)
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }
}
