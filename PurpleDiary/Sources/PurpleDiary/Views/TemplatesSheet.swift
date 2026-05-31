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
    }

    private var list: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Templates").font(.headline)
                Spacer()
                Button { addTemplate() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help("New template")
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
