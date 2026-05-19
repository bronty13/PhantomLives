import SwiftUI

/// Step 2 — per-format options. CSV: delimiter + has-header. JSON:
/// root path + NDJSON flag. Other formats: format-specific knobs as
/// their readers land.
struct ConfigureSourceStep: View {
    @ObservedObject var model: ImportWizardModel
    @State private var delimiter: String = ","
    @State private var hasHeader: Bool = true
    @State private var rootPath: String = "$"
    @State private var ndjson: Bool = false

    var body: some View {
        Form {
            switch model.draft.sourceFormat {
            case .csv: csvSection
            case .json: jsonSection
            default: deferredSection
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear { loadFromDraft() }
        .onChange(of: delimiter) { persist() }
        .onChange(of: hasHeader) { persist() }
        .onChange(of: rootPath) { persist() }
        .onChange(of: ndjson) { persist() }
    }

    // MARK: - CSV

    @ViewBuilder
    private var csvSection: some View {
        Section("CSV options") {
            HStack {
                Text("Delimiter")
                Spacer()
                TextField("", text: $delimiter)
                    .frame(width: 40)
                    .multilineTextAlignment(.center)
            }
            Toggle("First row is a header", isOn: $hasHeader)
            Text("Encoding is auto-detected (UTF-8 BOM, UTF-16 BOM, Latin-1 fallback). Override via the saved mapping JSON if needed — UI surface lands in Phase 2.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    // MARK: - JSON

    @ViewBuilder
    private var jsonSection: some View {
        Section("JSON options") {
            HStack {
                Text("Root path")
                Spacer()
                TextField("$", text: $rootPath)
                    .frame(width: 200)
                    .multilineTextAlignment(.trailing)
            }
            Toggle("Treat as NDJSON (one object per line)", isOn: $ndjson)
            Text("Path syntax: $ = root, .key, [n], [*]. Example: $.users[*]")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var deferredSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Label("Format not yet wired", systemImage: "hourglass")
                    .font(.headline)
                Text("\(model.draft.sourceFormat.displayName) readers land in a later phase. Step back and pick CSV or JSON.")
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Persistence

    private func loadFromDraft() {
        if case .string(let s) = model.draft.sourceOptions["delimiter"] { delimiter = s }
        if case .bool(let b) = model.draft.sourceOptions["hasHeader"] { hasHeader = b }
        if case .string(let s) = model.draft.sourceOptions["rootPath"] { rootPath = s }
        if case .bool(let b) = model.draft.sourceOptions["ndjson"] { ndjson = b }
    }

    private func persist() {
        var opts = model.draft.sourceOptions
        opts["delimiter"] = .string(delimiter)
        opts["hasHeader"] = .bool(hasHeader)
        opts["rootPath"] = .string(rootPath)
        opts["ndjson"] = .bool(ndjson)
        model.draft.sourceOptions = opts
    }
}
