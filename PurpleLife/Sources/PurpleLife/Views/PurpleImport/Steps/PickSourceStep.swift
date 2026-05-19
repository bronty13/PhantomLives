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
                    DropZone(
                        prompt: prompt,
                        acceptedExtensions: model.draft.sourceFormat.defaultFileExtensions,
                        acceptedDescription: "\(model.draft.sourceFormat.displayName) file"
                    ) { url in
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
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                        Text("Source: \(filename)").font(.callout)
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
        case .xlsx:     return "Phase 3 — readers land soon."
        case .docx:     return "Phase 5 — readers land soon (text-only, single record)."
        case .pdf:      return "Phase 5 — readers land soon (text-only, single record)."
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
