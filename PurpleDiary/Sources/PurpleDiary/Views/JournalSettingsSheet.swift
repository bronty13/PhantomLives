import SwiftUI

/// A Day One-style "Journal Settings" sheet: edit a journal's name, description,
/// color, entry sort order, per-view visibility, default template, and the
/// conceal-content flag in one place, with an entries/photos summary at the top
/// and Delete / Cancel / Update at the bottom. Edits a working copy and commits
/// the whole record once via `AppState.updateJournal` (GRDB writes every column,
/// so the new fields persist with no per-field plumbing).
struct JournalSettingsSheet: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    /// Working copy; the live journal isn't touched until Update.
    @State private var draft: Journal
    @State private var confirmingDelete = false

    init(journal: Journal) {
        _draft = State(initialValue: journal)
    }

    // MARK: - Derived

    private var journalEntries: [Entry] {
        appState.entries.filter { $0.journalId == draft.id }
    }
    private var entryCount: Int { journalEntries.count }
    private var photoCount: Int {
        journalEntries.reduce(0) { $0 + (appState.attachmentCountByEntry[$1.id] ?? 0) }
    }

    private var encryptionStatus: String {
        draft.isVault ? "Vault — sealed under its own passphrase"
                      : "On — encrypted at rest (SQLCipher, AES-256)"
    }
    private var encryptionHelp: String {
        draft.isVault
        ? "This is a vault journal: its entries are additionally sealed under a per-journal key, opaque even while the app is open, until you unlock it."
        : "Your whole journal database is encrypted at rest on disk. PurpleDiary has no network, so there is nothing transmitted to protect — see the Security & Privacy whitepaper in Help."
    }

    var body: some View {
        VStack(spacing: 0) {
            Text("\(entryCount) \(entryCount == 1 ? "entry" : "entries") · \(photoCount) \(photoCount == 1 ? "photo" : "photos")")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.top, 16)
                .padding(.bottom, 8)

            Form {
                Section {
                    TextField("Journal Name", text: $draft.name)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Description").font(.caption).foregroundStyle(.secondary)
                        TextEditor(text: $draft.journalDescription)
                            .frame(minHeight: 60)
                            .font(.body)
                            .overlay(RoundedRectangle(cornerRadius: 5)
                                .stroke(Color.secondary.opacity(0.25)))
                    }
                    ColorPicker("Color", selection: Binding(
                        get: { Color(hex: draft.colorHex) ?? .purple },
                        set: { draft.colorHex = $0.toHex() ?? draft.colorHex }
                    ), supportsOpacity: false)
                    Picker("Sort Order", selection: Binding(
                        get: { draft.sortModeValue },
                        set: { draft.sortMode = $0.rawValue }
                    )) {
                        ForEach(JournalSortMode.allCases) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                }

                Section {
                    LabeledContent("Encryption") {
                        HStack(spacing: 6) {
                            Text(encryptionStatus).foregroundStyle(.secondary)
                            Image(systemName: "questionmark.circle")
                                .foregroundStyle(.secondary)
                                .help(encryptionHelp)
                        }
                    }
                }

                Section("Visibility") {
                    Toggle("Show in All Entries", isOn: $draft.showInAllEntries)
                    Toggle("Show in On This Day", isOn: $draft.showInOnThisDay)
                    Toggle("Show in Calendar", isOn: $draft.showInCalendar)
                    Toggle("Conceal Content", isOn: $draft.concealContent)
                        .help("Blur this journal's entry previews in lists. Open an entry to read it.")
                }

                Section {
                    Picker("Default Template", selection: Binding(
                        get: { draft.defaultTemplateId ?? "" },
                        set: { draft.defaultTemplateId = $0.isEmpty ? nil : $0 }
                    )) {
                        Text("None").tag("")
                        ForEach(appState.templates) { t in
                            Text(t.name.isEmpty ? "Untitled" : t.name).tag(t.id)
                        }
                    }
                } footer: {
                    Text("A new blank entry in this journal starts from this template.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)

            Divider()
            HStack {
                if !draft.isDefault {
                    Button("Delete Journal", role: .destructive) { confirmingDelete = true }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Update") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
        }
        .frame(width: 480, height: 600)
        .confirmationDialog("Delete “\(draft.name)”?",
                            isPresented: $confirmingDelete, titleVisibility: .visible) {
            Button("Move entries to Journal, then delete") { delete(deleteEntries: false) }
            Button("Delete journal and its entries", role: .destructive) { delete(deleteEntries: true) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This journal has \(entryCount) \(entryCount == 1 ? "entry" : "entries").")
        }
    }

    private func save() {
        draft.name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
        if draft.name.isEmpty { draft.name = "Journal" }
        do { try appState.updateJournal(draft); dismiss() }
        catch { appState.errorMessage = error.localizedDescription }
    }

    private func delete(deleteEntries: Bool) {
        do { try appState.deleteJournal(id: draft.id, deleteEntries: deleteEntries); dismiss() }
        catch { appState.errorMessage = error.localizedDescription }
    }
}
