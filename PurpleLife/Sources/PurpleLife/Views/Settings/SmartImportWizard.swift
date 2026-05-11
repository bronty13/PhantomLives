import SwiftUI

/// Wizard sheet for the Smart Import flow. Three states: paste,
/// preview, done. The user pastes free-form text, hits Parse, sees a
/// preview table with checkboxes per parsed row (duplicates pre-
/// deselected), unchecks anything they don't want, hits Import.
///
/// Imported records use `source: "Imported"` to match the existing
/// CSV importer — keeps source-based filters working.
struct SmartImportWizard: View {
    @EnvironmentObject private var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var pastedText: String = ""
    @State private var parsed: [SmartWeightImporter.ParsedWeightEntry] = []
    @State private var didImport: Bool = false
    @State private var importedCount: Int = 0
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Image(systemName: "wand.and.stars")
                    .foregroundStyle(Color(hex: "#E8A93B") ?? .accentColor)
                Text("Smart Import — Weight").font(.title2).bold()
                Spacer()
                Button(parsed.isEmpty && !didImport ? "Cancel" : "Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding(20)
            Divider()
            Group {
                if didImport {
                    successView
                } else if parsed.isEmpty {
                    pasteView
                } else {
                    previewView
                }
            }
        }
        .frame(minWidth: 640, minHeight: 540)
    }

    // MARK: - Paste

    private var pasteView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Paste any text containing dates and weights — CSV / spreadsheet copy-paste / plain English all work. Examples:")
                .font(.callout).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 4) {
                Text("• 2024-01-15, 185.5").font(.caption.monospaced())
                Text("• January 2, 2024  184.0 lbs").font(.caption.monospaced())
                Text("• On 3/5/2024 I weighed 182 pounds").font(.caption.monospaced())
            }
            .foregroundStyle(.tertiary)

            TextEditor(text: $pastedText)
                .font(.body.monospaced())
                .frame(minHeight: 200)
                .scrollContentBackground(.hidden)
                .padding(8)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                )

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Parse Data") { runParse() }
                    .buttonStyle(.borderedProminent)
                    .disabled(pastedText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(20)
    }

    // MARK: - Preview

    private var previewView: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("\(parsed.count) row\(parsed.count == 1 ? "" : "s") parsed")
                    .font(.callout).foregroundStyle(.secondary)
                Text("·").foregroundStyle(.tertiary)
                Text("\(selectedCount) selected for import")
                    .font(.callout)
                Spacer()
                Button("Re-parse") {
                    parsed = []
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    headerRow
                    Divider()
                    ForEach(parsed.indices, id: \.self) { i in
                        previewRow(index: i)
                        Divider()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.bg.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 6))

            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Import \(selectedCount) entries") { runImport() }
                    .buttonStyle(.borderedProminent)
                    .disabled(selectedCount == 0)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
    }

    private var headerRow: some View {
        HStack(spacing: 12) {
            Text("").frame(width: 24)
            Text("Date")
                .font(.caption.weight(.semibold)).tracking(0.4)
                .textCase(.uppercase).foregroundStyle(.tertiary)
                .frame(width: 110, alignment: .leading)
            Text("Pounds")
                .font(.caption.weight(.semibold)).tracking(0.4)
                .textCase(.uppercase).foregroundStyle(.tertiary)
                .frame(width: 80, alignment: .leading)
            Text("Source line")
                .font(.caption.weight(.semibold)).tracking(0.4)
                .textCase(.uppercase).foregroundStyle(.tertiary)
            Spacer()
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
    }

    private func previewRow(index: Int) -> some View {
        HStack(spacing: 12) {
            Toggle("", isOn: Binding(
                get: { parsed[index].isSelected },
                set: { parsed[index].isSelected = $0 }
            ))
            .toggleStyle(.checkbox)
            .labelsHidden()
            .frame(width: 24)
            Text(dateLabel(parsed[index].date))
                .font(.body.monospacedDigit())
                .frame(width: 110, alignment: .leading)
                .foregroundStyle(parsed[index].isDuplicate ? .secondary : .primary)
            Text(String(format: "%.1f", parsed[index].pounds))
                .font(.body.monospacedDigit())
                .frame(width: 80, alignment: .leading)
                .foregroundStyle(parsed[index].isDuplicate ? .secondary : .primary)
            Text(parsed[index].sourceLine)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
            Spacer()
            if parsed[index].isDuplicate {
                Text("dup")
                    .font(.caption2)
                    .padding(.horizontal, 6).padding(.vertical, 1)
                    .background(Color.orange.opacity(0.2))
                    .foregroundStyle(.orange)
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
    }

    // MARK: - Done

    private var successView: some View {
        VStack(spacing: 10) {
            Spacer()
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 40))
                .foregroundStyle(.green)
            Text("Imported \(importedCount) Weight record\(importedCount == 1 ? "" : "s")")
                .font(.headline)
            Text("They appear in Records → Weight, and the latest one is now on the Today rail.")
                .font(.subheadline).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    // MARK: - Actions

    private var selectedCount: Int {
        parsed.filter(\.isSelected).count
    }

    private func runParse() {
        let existing = existingWeightDays()
        let result = SmartWeightImporter.parse(text: pastedText, existingDays: existing)
        if result.isEmpty {
            error = "No date+weight pairs found. Check the format and try again."
        } else {
            error = nil
            parsed = result
        }
    }

    /// Existing Weight record dates (start-of-day) used for duplicate
    /// pre-deselect during Smart Import.
    private func existingWeightDays() -> Set<Date> {
        let cal = Calendar.current
        let rows = (try? appState.database.fetchObjects(typeId: "Weight")) ?? []
        var set = Set<Date>()
        for r in rows {
            if let raw = r.fields()["date"] as? String,
               let d = parseISODateOnly(raw) ?? ISO8601DateFormatter().date(from: raw) {
                set.insert(cal.startOfDay(for: d))
            }
        }
        return set
    }

    private func runImport() {
        let toImport = parsed.filter(\.isSelected)
        var created = 0
        for entry in toImport {
            let isoDate = isoDateString(entry.date)
            do {
                _ = try ObjectEngine.create(
                    typeId: "Weight",
                    fields: [
                        "date": isoDate,
                        "pounds": entry.pounds,
                        "source": "Imported",
                    ]
                )
                created += 1
            } catch {
                self.error = "Import stopped after \(created) records: \(error.localizedDescription)"
                importedCount = created
                didImport = true
                appState.reloadAll()
                return
            }
        }
        importedCount = created
        didImport = true
        appState.reloadAll()
    }

    // MARK: - Date helpers

    private func dateLabel(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.string(from: d)
    }

    private func isoDateString(_ d: Date) -> String {
        // Weight type's Date field is .date (no time component); we
        // store as the calendar-day string the rest of PurpleLife
        // expects. The DatePicker round-trips this through
        // ISO8601DateFormatter when the user opens the detail sheet,
        // so emitting ISO-8601 is the safer choice.
        ISO8601DateFormatter().string(from: d)
    }

    private func parseISODateOnly(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f.date(from: s)
    }
}
