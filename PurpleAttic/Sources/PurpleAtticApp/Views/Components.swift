import SwiftUI
import AppKit

/// Present an NSOpenPanel to pick a folder; returns its path or nil.
func chooseDirectory(title: String) -> String? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = false
    panel.allowsMultipleSelection = false
    panel.title = title
    panel.prompt = "Choose"
    return panel.runModal() == .OK ? panel.url?.path : nil
}

/// Pick a `.photoslibrary` (a file package) or any folder.
func chooseLibrary(title: String) -> String? {
    let panel = NSOpenPanel()
    panel.canChooseDirectories = true
    panel.canChooseFiles = true
    panel.allowsMultipleSelection = false
    panel.treatsFilePackagesAsDirectories = false // so a .photoslibrary is selectable as one item
    panel.title = title
    panel.prompt = "Choose"
    return panel.runModal() == .OK ? panel.url?.path : nil
}

/// Labeled path row: a text field plus a "Choose…" button.
struct PathField: View {
    let label: String
    @Binding var path: String
    var chooser: (String) -> String? = chooseDirectory
    var placeholder: String = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.subheadline.weight(.medium))
            HStack(spacing: 6) {
                TextField(placeholder, text: $path)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(.body, design: .monospaced))
                Button("Choose…") {
                    if let chosen = chooser(label) { path = chosen }
                }
            }
        }
    }
}

/// Section card wrapper for settings groups.
struct Card<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 10))
    }
}
