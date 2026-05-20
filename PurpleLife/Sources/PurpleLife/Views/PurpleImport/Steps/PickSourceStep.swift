import SwiftUI
import UniformTypeIdentifiers

/// Step 1 — pick a source. Three affordances:
///   1. Drag-and-drop onto a DropZone (or click to open NSOpenPanel).
///   2. Paste raw text (mostly CSV / JSON).
///   3. Choose a format manually (auto-detected from extension when
///      the user picks a file, but they can override here).
struct PickSourceStep: View {
    @ObservedObject var model: ImportWizardModel
    @State private var paste: String = ""
    @State private var showingPaste: Bool = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("What do you want to import?")
                    .font(.title3).bold()

                if !showingPaste {
                    DropZone(prompt: prompt) { url in
                        model.chooseFile(url)
                    }
                } else {
                    pastePane
                }

                HStack {
                    Toggle("Paste text instead", isOn: $showingPaste)
                        .toggleStyle(.switch)
                    Spacer()
                }

                Divider().padding(.vertical, 4)

                VStack(alignment: .leading, spacing: 6) {
                    Text("Source format").font(.headline)
                    Picker("Source format", selection: $model.draft.sourceFormat) {
                        ForEach(PurpleImport.SourceFormat.allCases, id: \.self) { fmt in
                            HStack {
                                Image(systemName: fmt.systemImage)
                                Text(fmt.displayName)
                            }
                            .tag(fmt)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text(formatHelp)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let filename = model.pickedFilename {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 8) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            Text("Source: \(filename)").font(.callout)
                        }
                        HStack(spacing: 8) {
                            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                            Text("Auto-detected format: ")
                                .font(.caption).foregroundStyle(.secondary)
                            + Text(model.draft.sourceFormat.displayName)
                                .font(.caption.weight(.semibold))
                            Spacer()
                            Text("Override above if wrong")
                                .font(.caption2).foregroundStyle(.tertiary)
                        }
                    }
                }
            }
            .padding(20)
        }
    }

    private var prompt: String {
        "Drop a \(model.draft.sourceFormat.displayName) file here, or click to choose"
    }

    private var formatHelp: String {
        switch model.draft.sourceFormat {
        case .csv:      return "Supported. Header row auto-detected; override in the next step."
        case .json:     return "Supported. Top-level array, NDJSON, or single object."
        case .markdown: return "Supported. GFM pipe tables, YAML/TOML frontmatter, or plain document."
        case .xml:      return "Supported. Tree-shaped; the largest repeating child element becomes the row collection (override via root path in the next step)."
        case .xlsx:     return "Supported. Picks the first sheet by default; sheet, header row, and column range are tunable in the next step."
        case .docx:     return "Supported (text-only). One record per document, body in $._body. Tables / track-changes / comments aren't parsed in v1."
        case .pdf:      return "Supported (text-only). One record per document, body in $._body. Pages joined with a form-feed separator; configurable in the next step."
        }
    }

    private var pastePane: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Paste your CSV / JSON here. The wizard treats it as a tempfile under the hood.")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $paste)
                .font(.body.monospaced())
                .frame(minHeight: 140)
                .scrollContentBackground(.hidden)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color.secondary.opacity(0.3), lineWidth: 0.5)
                )
            HStack {
                Spacer()
                Button("Use pasted text") {
                    model.choosePaste(paste)
                }
                .disabled(paste.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
    }
}
