import SwiftUI

struct ImportWizardView: View {
    @EnvironmentObject var appState: AppState

    @State private var pasteText = ""
    @State private var parsedEntries: [ParsedEntry] = []
    @State private var isParsed = false
    @State private var importResult: String? = nil
    @State private var selectedIds = Set<UUID>()

    private var unit: WeightUnit { appState.settings.weightUnit }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                header

                if !isParsed {
                    pasteStep
                } else {
                    previewStep
                }
            }
            .padding(24)
        }
    }

    var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Smart Import")
                .font(.largeTitle.weight(.bold))
            Text("Paste any text containing dates and weights — the app will extract what it can.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    var pasteStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Paste your data below")
                .font(.headline)
            Text("Supports CSV, TSV, plain text, spreadsheet copy-paste — any format containing dates (ISO, M/D/YYYY, month name) and weights.")
                .font(.caption)
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.ultraThinMaterial)
                    .frame(minHeight: 200)
                if pasteText.isEmpty {
                    Text("e.g.:\n2024-01-01, 185.5\nJanuary 2 2024 184.0\n01/03/2024  183.2")
                        .font(.system(.body, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .padding(12)
                }
                TextEditor(text: $pasteText)
                    .font(.system(.body, design: .monospaced))
                    .scrollContentBackground(.hidden)
                    .background(.clear)
                    .padding(8)
                    .frame(minHeight: 200)
            }

            HStack {
                Button("Parse Data") {
                    parse()
                }
                .buttonStyle(.borderedProminent)
                .tint(appState.effectiveAccentColor)
                .disabled(pasteText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Button("Clear") {
                    pasteText = ""
                    parsedEntries = []
                    isParsed = false
                    importResult = nil
                }
                .buttonStyle(.bordered)
            }
        }
    }

    var previewStep: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Preview — \(parsedEntries.count) entries found")
                    .font(.headline)
                Spacer()
                Button("Back") {
                    isParsed = false
                    parsedEntries = []
                    importResult = nil
                }
                .buttonStyle(.bordered)
            }

            if let result = importResult {
                Text(result)
                    .font(.subheadline)
                    .foregroundStyle(.green)
                    .padding(12)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            Text("Deselect any entries you don't want to import. Duplicates are pre-deselected.")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack {
                Button("Select All") {
                    for i in parsedEntries.indices { parsedEntries[i].isSelected = true }
                }
                .buttonStyle(.bordered)
                Button("Deselect All") {
                    for i in parsedEntries.indices { parsedEntries[i].isSelected = false }
                }
                .buttonStyle(.bordered)
                Spacer()
                let toImport = parsedEntries.filter { $0.isSelected }.count
                Button("Import \(toImport) entries") {
                    importSelected()
                }
                .buttonStyle(.borderedProminent)
                .tint(appState.effectiveAccentColor)
                .disabled(toImport == 0)
            }

            VStack(spacing: 0) {
                previewHeader
                Divider()
                ForEach(parsedEntries.indices, id: \.self) { i in
                    previewRow(index: i)
                    if i < parsedEntries.count - 1 { Divider().opacity(0.4) }
                }
            }
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
    }

    var previewHeader: some View {
        HStack {
            Text("✓").frame(width: 24)
            Text("Date").frame(width: 110, alignment: .leading)
            Text("Weight (\(unit.label))").frame(width: 100, alignment: .leading)
            Text("Status").frame(width: 80, alignment: .leading)
            Spacer()
        }
        .font(.caption.weight(.semibold))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    func previewRow(index: Int) -> some View {
        let entry = parsedEntries[index]
        let displayW = unit == .lbs ? entry.weightLbs : entry.weightLbs * 0.453592
        return HStack {
            Toggle("", isOn: Binding(
                get: { parsedEntries[index].isSelected },
                set: { parsedEntries[index].isSelected = $0 }
            ))
            .toggleStyle(.checkbox)
            .frame(width: 24)

            Text(entry.date)
                .frame(width: 110, alignment: .leading)
                .font(.system(.body, design: .monospaced))

            Text(String(format: "%.1f", displayW))
                .frame(width: 100, alignment: .leading)
                .fontWeight(.semibold)

            Text(entry.isDuplicate ? "Duplicate" : "New")
                .font(.caption)
                .foregroundStyle(entry.isDuplicate ? .orange : .green)
                .frame(width: 80, alignment: .leading)

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .opacity(parsedEntries[index].isSelected ? 1.0 : 0.4)
    }

    private func parse() {
        let existing = appState.existingDates()
        var entries = ImportService.parse(text: pasteText, unit: unit, existingDates: existing)
        for i in entries.indices {
            if entries[i].isDuplicate { entries[i].isSelected = false }
        }
        parsedEntries = entries
        isParsed = true
        importResult = nil
    }

    private func importSelected() {
        let toImport = parsedEntries.filter { $0.isSelected }
        appState.importEntries(toImport)
        importResult = "✓ Imported \(toImport.count) entries successfully."
        for i in parsedEntries.indices {
            if parsedEntries[i].isSelected {
                parsedEntries[i].isSelected = false
                parsedEntries[i].isDuplicate = true
            }
        }
    }
}
