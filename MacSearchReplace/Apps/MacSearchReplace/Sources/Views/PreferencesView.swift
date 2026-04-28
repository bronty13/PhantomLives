import SwiftUI

struct PreferencesView: View {
    @ObservedObject var prefs = Preferences.shared

    var body: some View {
        TabView {
            generalTab.tabItem { Label("General", systemImage: "gearshape") }
            editorsTab.tabItem { Label("Editors", systemImage: "pencil.and.scribble") }
            archivesTab.tabItem { Label("Archives", systemImage: "doc.zipper") }
            displayTab.tabItem { Label("Display", systemImage: "rectangle.split.3x1") }
            performanceTab.tabItem { Label("Performance", systemImage: "speedometer") }
        }
        .frame(width: 520, height: 360)
        .padding()
    }

    private var generalTab: some View {
        Form {
            Toggle("Enable backups by default when replacing", isOn: $prefs.backupsEnabledByDefault)
            Divider()
            Section("Recent Folders") {
                if prefs.recentRoots.isEmpty {
                    Text("(none)").foregroundStyle(.secondary)
                } else {
                    ForEach(prefs.recentRoots, id: \.self) { p in
                        Text(p).font(.system(.caption, design: .monospaced))
                            .lineLimit(1).truncationMode(.middle)
                    }
                    Button("Clear Recent Folders") { prefs.clearRecentRoots() }
                }
            }
        }
        .padding()
    }

    private var editorsTab: some View {
        Form {
            editorRow(title: "Text editor:",
                      path: $prefs.textEditorPath,
                      detect: ["/Applications/BBEdit.app",
                               "/Applications/Visual Studio Code.app",
                               "/Applications/Sublime Text.app",
                               "/Applications/Xcode.app",
                               "/Applications/TextEdit.app"])
            editorRow(title: "Binary editor:",
                      path: $prefs.binaryEditorPath,
                      detect: ["/Applications/Hex Fiend.app",
                               "/Applications/0xED.app",
                               "/Applications/iHex.app"])
        }
        .padding()
    }

    private var archivesTab: some View {
        Form {
            Toggle("Search inside .zip archives", isOn: $prefs.searchInsideArchives)
            Toggle("Search inside .docx / .xlsx / .pptx", isOn: $prefs.searchInsideOOXML)
            Toggle("Search PDF text (read-only)", isOn: $prefs.searchInsidePDFs)
            Text("Note: replacements inside archives rewrite the entire archive.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
    }

    private var displayTab: some View {
        Form {
            HStack {
                Text("Max preview line length:")
                Stepper(value: $prefs.maxPreviewLineLength, in: 80...4000, step: 40) {
                    Text("\(prefs.maxPreviewLineLength) chars").monospacedDigit()
                }
            }
            HStack {
                Text("Context lines (above & below):")
                Stepper(value: $prefs.contextLines, in: 0...30) {
                    Text("\(prefs.contextLines)").monospacedDigit()
                }
            }
        }
        .padding()
    }

    private var performanceTab: some View {
        Form {
            HStack {
                Text("Large-file streaming threshold:")
                Stepper(value: $prefs.largeFileThresholdMB, in: 1...4096, step: 8) {
                    Text("\(prefs.largeFileThresholdMB) MB").monospacedDigit()
                }
            }
            Text("Files above this size are processed with chunked I/O instead of being read fully into memory.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding()
    }

    private func editorRow(title: String, path: Binding<String>, detect: [String]) -> some View {
        HStack(spacing: 6) {
            Text(title).frame(width: 100, alignment: .trailing)
            TextField("/Applications/Foo.app", text: path)
                .textFieldStyle(.roundedBorder)
                .font(.system(.caption, design: .monospaced))
            Button("Choose…") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = true
                panel.canChooseDirectories = false
                panel.allowedContentTypes = [.application]
                if panel.runModal() == .OK, let url = panel.url {
                    path.wrappedValue = url.path
                }
            }
            Menu("Detect") {
                ForEach(detect, id: \.self) { p in
                    if FileManager.default.fileExists(atPath: p) {
                        Button(URL(fileURLWithPath: p).lastPathComponent) { path.wrappedValue = p }
                    }
                }
            }
            .frame(width: 80)
        }
    }
}
