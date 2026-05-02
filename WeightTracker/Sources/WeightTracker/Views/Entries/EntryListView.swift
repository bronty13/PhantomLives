import SwiftUI

struct EntryListView: View {
    @EnvironmentObject var appState: AppState
    @State private var selectedDates = Set<String>()
    @State private var editingEntry: WeightEntry? = nil
    @State private var showDeleteConfirm = false
    @State private var sortAscending = false
    @State private var searchText = ""

    private var unit: WeightUnit { appState.settings.weightUnit }

    var displayedEntries: [WeightEntry] {
        let filtered = searchText.isEmpty ? appState.entries : appState.entries.filter {
            $0.date.localizedCaseInsensitiveContains(searchText) ||
            $0.notesMd.localizedCaseInsensitiveContains(searchText)
        }
        let sorted = filtered.sorted { $0.date < $1.date }
        return sortAscending ? sorted : sorted.reversed()
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            List(displayedEntries, id: \.date, selection: $selectedDates) { entry in
                EntryRowView(entry: entry, unit: unit, accent: appState.effectiveAccentColor)
                    .tag(entry.date)
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { editingEntry = entry }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
        .searchable(text: $searchText, prompt: "Search entries…")
        .sheet(isPresented: Binding(get: { editingEntry != nil }, set: { if !$0 { editingEntry = nil } })) {
            if editingEntry != nil {
                EntryDetailView(
                    entry: Binding(get: { editingEntry! }, set: { editingEntry = $0 }),
                    onSave: { editingEntry = nil },
                    onCancel: { editingEntry = nil }
                )
                .environmentObject(appState)
            }
        }
        .confirmationDialog(
            "Delete \(selectedDates.count) \(selectedDates.count == 1 ? "entry" : "entries")?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                let ids = appState.entries
                    .filter { selectedDates.contains($0.date) }
                    .compactMap { $0.rowId }
                appState.deleteEntries(ids: ids)
                selectedDates.removeAll()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This action cannot be undone.")
        }
    }

    var toolbar: some View {
        HStack(spacing: 12) {
            Text("Entries")
                .font(.title2.weight(.bold))
            Text("(\(appState.entries.count))")
                .foregroundStyle(.secondary)
            Button {
                sortAscending.toggle()
            } label: {
                Image(systemName: sortAscending ? "arrow.up" : "arrow.down")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help(sortAscending ? "Oldest first" : "Newest first")
            Spacer()
            if !selectedDates.isEmpty {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete (\(selectedDates.count))", systemImage: "trash")
                }
                .buttonStyle(.bordered)
            }
            Button {
                NotificationCenter.default.post(name: .addEntryRequested, object: nil)
            } label: {
                Label("Add Entry", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
            .tint(appState.effectiveAccentColor)

            ExportMenuButton()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
    }
}

struct EntryRowView: View {
    let entry: WeightEntry
    let unit: WeightUnit
    let accent: Color

    var body: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.date)
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.primary)
                if !entry.notesMd.isEmpty {
                    Text(entry.notesMd)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(String(format: "%.1f", entry.displayWeight(unit: unit)))
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.primary)
                Text(unit.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            if entry.photoBlob != nil {
                Image(systemName: "photo")
                    .foregroundStyle(accent.opacity(0.7))
                    .font(.caption)
            }
        }
        .padding(.vertical, 4)
    }
}

struct ExportMenuButton: View {
    @EnvironmentObject var appState: AppState

    var body: some View {
        Menu {
            Button("Export CSV…") { export(.csv) }
            Button("Export Markdown…") { export(.md) }
            Button("Export XLSX…") { export(.xlsx) }
            Button("Export DOCX…") { export(.docx) }
            Divider()
            Button("Export PDF Report…") { export(.pdf) }
        } label: {
            Label("Export", systemImage: "square.and.arrow.up")
        }
        .menuStyle(.borderedButton)
    }

    enum Format { case csv, md, xlsx, docx, pdf }

    private var defaultOutputDir: URL {
        let downloads = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first!
        let dir = downloads.appendingPathComponent("WeightTracker")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func export(_ format: Format) {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.directoryURL = defaultOutputDir
        let unit = appState.settings.weightUnit
        let entries = appState.entries

        switch format {
        case .csv:
            panel.nameFieldStringValue = "WeightTracker.csv"
            panel.allowedContentTypes = [.commaSeparatedText]
            if panel.runModal() == .OK, let url = panel.url {
                try? ExportService.exportCSV(entries: entries, unit: unit)
                    .write(to: url, atomically: true, encoding: .utf8)
            }
        case .md:
            panel.nameFieldStringValue = "WeightTracker.md"
            if panel.runModal() == .OK, let url = panel.url {
                try? ExportService.exportMarkdown(entries: entries, unit: unit, stats: appState.stats, username: appState.settings.username)
                    .write(to: url, atomically: true, encoding: .utf8)
            }
        case .xlsx:
            panel.nameFieldStringValue = "WeightTracker.xlsx"
            if panel.runModal() == .OK, let url = panel.url {
                ExportService.exportXLSX(entries: entries, unit: unit).map { try? $0.write(to: url) }
            }
        case .docx:
            panel.nameFieldStringValue = "WeightTracker.docx"
            if panel.runModal() == .OK, let url = panel.url {
                ExportService.exportDOCX(entries: entries, unit: unit, stats: appState.stats, username: appState.settings.username).map { try? $0.write(to: url) }
            }
        case .pdf:
            panel.nameFieldStringValue = "WeightTracker Report.pdf"
            panel.allowedContentTypes = [.pdf]
            if panel.runModal() == .OK, let url = panel.url {
                Task { @MainActor in
                    let pdfData = ExportService.exportPDFReport(
                        entries: entries,
                        stats: appState.stats,
                        unit: unit,
                        username: appState.settings.username,
                        chartImage: nil
                    )
                    try? pdfData.write(to: url)
                }
            }
        }
    }
}
