import SwiftUI

/// Step 4 — pick the destination format + tune per-format options.
/// Layout mirrors Purple Import's ConfigureSourceStep: format picker
/// at top, format-specific options below.
struct PickFormatStep: View {
    @ObservedObject var model: ExportWizardModel

    @State private var csvDelimiter: String = ","
    @State private var csvQuoteAlways: Bool = false
    @State private var jsonShape: String = "arrayOfObjects"
    @State private var jsonPretty: Bool = true
    @State private var markdownShape: String = "table"
    @State private var xmlRoot: String = "records"
    @State private var xmlRecord: String = "record"

    var body: some View {
        Form {
            Section("Format") {
                Picker("", selection: $model.draft.format) {
                    ForEach(PurpleExport.DestinationFormat.allCases, id: \.self) { f in
                        HStack {
                            Image(systemName: f.systemImage)
                            Text(f.displayName)
                        }
                        .tag(f)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                Text(formatHelp)
                    .font(.caption).foregroundStyle(.secondary)
            }

            switch model.draft.format {
            case .csv:      csvSection
            case .json:     jsonSection
            case .markdown: markdownSection
            case .xml:      xmlSection
            case .html, .pdf:
                Section { Text("No additional options.").font(.caption).foregroundStyle(.secondary) }
            case .xlsx, .docx:
                Section {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Writer not yet wired", systemImage: "hourglass")
                            .font(.headline)
                        Text("\(model.draft.format.displayName) export lands in a later phase. Pick CSV / JSON / Markdown / XML / HTML / PDF for now.")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .onAppear { loadFromDraft() }
        .onChange(of: csvDelimiter)   { persist() }
        .onChange(of: csvQuoteAlways) { persist() }
        .onChange(of: jsonShape)      { persist() }
        .onChange(of: jsonPretty)     { persist() }
        .onChange(of: markdownShape)  { persist() }
        .onChange(of: xmlRoot)        { persist() }
        .onChange(of: xmlRecord)      { persist() }
    }

    private var formatHelp: String {
        switch model.draft.format {
        case .csv:      return "Comma-separated values. Round-trips through Excel / Numbers / any data-importer."
        case .json:     return "JSON. Pick array-of-objects (default) for downstream loaders, NDJSON for streaming, or nested for a self-describing envelope with the schema embedded."
        case .markdown: return "Markdown. Default emits a GFM pipe table; switch to list-per-record for note-style output."
        case .xml:      return "XML. Root + record element names are configurable below."
        case .html:     return "Standalone HTML document with inline CSS. Open in any browser; print to share."
        case .pdf:      return "PDF rendered from the same HTML pipeline as legacy exports."
        case .xlsx:     return "Phase 4.5 — minimal OOXML emitter on top of ZIPFoundation."
        case .docx:     return "Phase 5 — text-only single-document write."
        }
    }

    // MARK: - CSV

    @ViewBuilder
    private var csvSection: some View {
        Section("CSV options") {
            HStack {
                Text("Delimiter")
                Spacer()
                TextField("", text: $csvDelimiter)
                    .frame(width: 40)
                    .multilineTextAlignment(.center)
            }
            Toggle("Always quote every cell", isOn: $csvQuoteAlways)
        }
    }

    // MARK: - JSON

    @ViewBuilder
    private var jsonSection: some View {
        Section("JSON options") {
            Picker("Shape", selection: $jsonShape) {
                Text("Array of objects").tag("arrayOfObjects")
                Text("NDJSON (one per line)").tag("ndjson")
                Text("Nested envelope (with schema)").tag("nested")
            }
            .pickerStyle(.menu)
            Toggle("Pretty-print (whitespace + sort)", isOn: $jsonPretty)
        }
    }

    // MARK: - Markdown

    @ViewBuilder
    private var markdownSection: some View {
        Section("Markdown options") {
            Picker("Shape", selection: $markdownShape) {
                Text("GFM pipe table").tag("table")
                Text("List per record").tag("listPerRecord")
            }
            .pickerStyle(.menu)
        }
    }

    // MARK: - XML

    @ViewBuilder
    private var xmlSection: some View {
        Section("XML options") {
            HStack {
                Text("Root element")
                Spacer()
                TextField("records", text: $xmlRoot)
                    .frame(width: 180)
                    .multilineTextAlignment(.trailing)
            }
            HStack {
                Text("Record element")
                Spacer()
                TextField("record", text: $xmlRecord)
                    .frame(width: 180)
                    .multilineTextAlignment(.trailing)
            }
        }
    }

    // MARK: - Persistence

    private func loadFromDraft() {
        let o = model.draft.formatOptions
        csvDelimiter   = o.csvDelimiter
        csvQuoteAlways = o.csvQuoteAlways
        jsonShape      = o.jsonShape.rawValue
        jsonPretty     = o.jsonPrettyPrint
        markdownShape  = o.markdownShape.rawValue
        xmlRoot        = o.xmlRootElement
        xmlRecord      = o.xmlRecordElement
    }

    private func persist() {
        var o = model.draft.formatOptions
        o.csvDelimiter   = csvDelimiter
        o.csvQuoteAlways = csvQuoteAlways
        o.jsonShape      = PurpleExport.FormatOptions.JSONShape(rawValue: jsonShape) ?? .arrayOfObjects
        o.jsonPrettyPrint = jsonPretty
        o.markdownShape  = PurpleExport.FormatOptions.MarkdownShape(rawValue: markdownShape) ?? .table
        o.xmlRootElement = xmlRoot
        o.xmlRecordElement = xmlRecord
        model.draft.formatOptions = o
    }
}
