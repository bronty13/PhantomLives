import AppKit
import UniformTypeIdentifiers

/// Open/save panels and folder enumeration. The markdown UTType is declared in
/// the app's Info.plist (`net.daringfireball.markdown`); we also accept plain
/// text and the common markdown extensions.
enum FileService {
    static let markdownExtensions: Set<String> = ["md", "markdown", "mdown", "mkd", "mkdn", "mdtext", "text", "txt"]

    static var markdownContentTypes: [UTType] {
        var types: [UTType] = []
        if let md = UTType("net.daringfireball.markdown") { types.append(md) }
        types.append(.plainText)
        return types
    }

    static func runOpenPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = markdownContentTypes
        panel.allowsOtherFileTypes = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func runOpenFolderPanel() -> URL? {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.prompt = "Open Folder"
        return panel.runModal() == .OK ? panel.url : nil
    }

    static func runSavePanel(suggestedName: String) -> URL? {
        let panel = NSSavePanel()
        var name = suggestedName
        if (name as NSString).pathExtension.isEmpty { name += ".md" }
        panel.nameFieldStringValue = name
        if let md = UTType("net.daringfireball.markdown") {
            panel.allowedContentTypes = [md]
        }
        panel.allowsOtherFileTypes = true
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }

    /// Markdown files directly inside `folder`, sorted case-insensitively.
    static func markdownFiles(in folder: URL) -> [URL] {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: folder,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]) else { return [] }
        return entries
            .filter { markdownExtensions.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }
}
