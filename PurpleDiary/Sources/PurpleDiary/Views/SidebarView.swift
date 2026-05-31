import SwiftUI

/// Fixed-width sidebar: app title, the top-level sections, a Journals switcher,
/// and a small stats footer. Rows are plain tappable buttons (not `List`
/// selection) to stay consistent with the manual-layout pattern.
struct SidebarView: View {
    @EnvironmentObject var appState: AppState

    @State private var showingNewJournal = false
    @State private var newJournalName = ""
    @State private var renaming: Journal?
    @State private var renameText = ""
    @State private var deleting: Journal?

    /// Preset colors offered when recoloring a journal.
    private let presetColors = ["#7C5CFF", "#3FA9F5", "#3FB950", "#E8A93B", "#F08C2E", "#D14B5C", "#888888"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            Divider()
            ScrollView {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(AppState.Section.allCases, id: \.self) { section in
                        sectionRow(section)
                    }
                    journalsSection
                }
                .padding(.vertical, 6)
            }
            Spacer(minLength: 0)
            Divider()
            footer
        }
        .alert("New Journal", isPresented: $showingNewJournal) {
            TextField("Name", text: $newJournalName)
            Button("Create") { createJournal() }
            Button("Cancel", role: .cancel) { newJournalName = "" }
        } message: {
            Text("Name your new journal. You can hide it later to keep it out of the timeline, calendar, and search.")
        }
        .alert("Rename Journal", isPresented: Binding(
            get: { renaming != nil }, set: { if !$0 { renaming = nil } }
        )) {
            TextField("Name", text: $renameText)
            Button("Save") { commitRename() }
            Button("Cancel", role: .cancel) { renaming = nil }
        }
        .confirmationDialog(
            deleting.map { "Delete “\($0.name)”?" } ?? "Delete journal?",
            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
            titleVisibility: .visible,
            presenting: deleting
        ) { journal in
            if deleteCount > 0 {
                Button("Move \(deleteCount) \(deleteCount == 1 ? "entry" : "entries") to “Journal”") {
                    try? appState.deleteJournal(id: journal.id, deleteEntries: false)
                }
                Button("Delete journal and \(deleteCount) \(deleteCount == 1 ? "entry" : "entries")", role: .destructive) {
                    try? appState.deleteJournal(id: journal.id, deleteEntries: true)
                }
            } else {
                Button("Delete", role: .destructive) {
                    try? appState.deleteJournal(id: journal.id, deleteEntries: true)
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { journal in
            if deleteCount > 0 {
                Text("“\(journal.name)” has \(deleteCount) \(deleteCount == 1 ? "entry" : "entries"). Move them to your default journal, or delete them along with the journal (this can't be undone).")
            } else {
                Text("This journal has no entries.")
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "book.closed.fill")
                .foregroundStyle(appState.effectiveAccentColor)
                .font(.title3)
            Text("PurpleDiary")
                .font(.headline)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private func sectionRow(_ section: AppState.Section) -> some View {
        let isSelected = appState.selectedSection == section
        return Button {
            appState.selectedSection = section
        } label: {
            HStack(spacing: 10) {
                Image(systemName: section.systemImage)
                    .frame(width: 18)
                    .foregroundStyle(isSelected ? appState.effectiveAccentColor : .secondary)
                Text(section.title)
                    .foregroundStyle(.primary)
                Spacer()
                if section == .timeline {
                    Text("\(appState.visibleEntries.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                isSelected ? appState.effectiveAccentColor.opacity(0.18) : Color.clear,
                in: RoundedRectangle(cornerRadius: 6)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }

    // MARK: - Journals

    private var journalsSection: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("JOURNALS")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.secondary)
                Spacer()
                Button {
                    newJournalName = ""
                    showingNewJournal = true
                } label: {
                    Image(systemName: "plus")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("New journal")
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 2)

            allJournalsRow
            ForEach(appState.journals) { journal in
                journalRow(journal)
            }
        }
    }

    private var allJournalsRow: some View {
        let isSelected = appState.selectedJournalId == nil
        let total = appState.journals
            .filter { !$0.isHidden || appState.unlockedHiddenJournalIds.contains($0.id) }
            .reduce(0) { $0 + (appState.entryCountByJournal[$1.id] ?? 0) }
        return Button {
            appState.selectedJournalId = nil
        } label: {
            journalRowLabel(symbol: "books.vertical", color: .secondary,
                            name: "All Journals", count: total,
                            locked: false, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
    }

    private func journalRow(_ journal: Journal) -> some View {
        let locked = journal.isHidden && !appState.unlockedHiddenJournalIds.contains(journal.id)
        let isSelected = appState.selectedJournalId == journal.id
        return Button {
            if locked {
                Task { await appState.unlockHiddenJournal(journal.id)
                       if appState.unlockedHiddenJournalIds.contains(journal.id) {
                           appState.selectedJournalId = journal.id
                       } }
            } else {
                appState.selectedJournalId = journal.id
            }
        } label: {
            journalRowLabel(symbol: journal.symbol,
                            color: Color(hex: journal.colorHex) ?? .purple,
                            name: journal.name,
                            count: appState.entryCountByJournal[journal.id] ?? 0,
                            locked: locked, isSelected: isSelected)
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 6)
        .contextMenu { journalContextMenu(journal) }
    }

    private func journalRowLabel(symbol: String, color: Color, name: String,
                                 count: Int, locked: Bool, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: locked ? "lock.fill" : symbol)
                .frame(width: 18)
                .foregroundStyle(locked ? .secondary : color)
            Text(name)
                .foregroundStyle(.primary)
                .lineLimit(1)
            Spacer()
            Text(locked ? "🔒" : "\(count)")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            isSelected ? appState.effectiveAccentColor.opacity(0.18) : Color.clear,
            in: RoundedRectangle(cornerRadius: 6)
        )
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func journalContextMenu(_ journal: Journal) -> some View {
        Button("Rename…") {
            renameText = journal.name
            renaming = journal
        }
        Menu("Color") {
            ForEach(presetColors, id: \.self) { hex in
                Button {
                    var j = journal; j.colorHex = hex
                    try? appState.updateJournal(j)
                } label: {
                    Label(hex, systemImage: journal.colorHex == hex ? "checkmark.circle.fill" : "circle.fill")
                }
            }
        }
        Button(journal.isHidden ? "Show in Timeline & Search" : "Hide (lock out of Timeline & Search)") {
            try? appState.setJournalHidden(!journal.isHidden, journalId: journal.id)
        }
        if !journal.isDefault {
            Divider()
            Button(role: .destructive) { deleting = journal } label: { Text("Delete Journal…") }
        }
    }

    private var deleteCount: Int { deleting.map { appState.entryCountByJournal[$0.id] ?? 0 } ?? 0 }

    private func createJournal() {
        let name = newJournalName
        newJournalName = ""
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        do {
            let j = try appState.createJournal(name: name)
            appState.selectedJournalId = j.id
        } catch {
            appState.errorMessage = error.localizedDescription
        }
    }

    private func commitRename() {
        guard var j = renaming else { return }
        renaming = nil
        let name = renameText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        j.name = name
        try? appState.updateJournal(j)
    }

    private var footer: some View {
        let totalWords = appState.visibleEntries.reduce(0) { $0 + $1.wordCount }
        return VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text("Entries").foregroundStyle(.secondary)
                Spacer()
                Text("\(appState.visibleEntries.count)")
            }
            HStack {
                Text("Words").foregroundStyle(.secondary)
                Spacer()
                Text("\(totalWords)")
            }
        }
        .font(.caption)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }
}
