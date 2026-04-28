import Foundation
import SwiftUI
import AppKit

/// Singleton that persists app preferences to UserDefaults and broadcasts
/// changes to observers. Used by the Preferences window and the rest of
/// the UI.
@MainActor
final class Preferences: ObservableObject {

    static let shared = Preferences()

    private let defaults = UserDefaults.standard

    // External editors
    @Published var textEditorPath: String {
        didSet { defaults.set(textEditorPath, forKey: "textEditorPath") }
    }
    @Published var binaryEditorPath: String {
        didSet { defaults.set(binaryEditorPath, forKey: "binaryEditorPath") }
    }

    // Backups
    @Published var backupsEnabledByDefault: Bool {
        didSet { defaults.set(backupsEnabledByDefault, forKey: "backupsEnabledByDefault") }
    }

    // Archive search defaults
    @Published var searchInsideArchives: Bool {
        didSet { defaults.set(searchInsideArchives, forKey: "searchInsideArchives") }
    }
    @Published var searchInsideOOXML: Bool {
        didSet { defaults.set(searchInsideOOXML, forKey: "searchInsideOOXML") }
    }
    @Published var searchInsidePDFs: Bool {
        didSet { defaults.set(searchInsidePDFs, forKey: "searchInsidePDFs") }
    }

    // Display
    @Published var maxPreviewLineLength: Int {
        didSet { defaults.set(maxPreviewLineLength, forKey: "maxPreviewLineLength") }
    }
    @Published var contextLines: Int {
        didSet { defaults.set(contextLines, forKey: "contextLines") }
    }

    // Performance
    @Published var largeFileThresholdMB: Int {
        didSet { defaults.set(largeFileThresholdMB, forKey: "largeFileThresholdMB") }
    }

    // Recent folders
    @Published var recentRoots: [String] {
        didSet { defaults.set(recentRoots, forKey: "recentRoots") }
    }

    private init() {
        textEditorPath           = defaults.string(forKey: "textEditorPath") ?? Self.detectTextEditor()
        binaryEditorPath         = defaults.string(forKey: "binaryEditorPath") ?? "/Applications/Hex Fiend.app"
        backupsEnabledByDefault  = (defaults.object(forKey: "backupsEnabledByDefault") as? Bool) ?? true
        searchInsideArchives     = (defaults.object(forKey: "searchInsideArchives") as? Bool) ?? false
        searchInsideOOXML        = (defaults.object(forKey: "searchInsideOOXML")    as? Bool) ?? false
        searchInsidePDFs         = (defaults.object(forKey: "searchInsidePDFs")     as? Bool) ?? false
        maxPreviewLineLength     = (defaults.object(forKey: "maxPreviewLineLength") as? Int)  ?? 400
        contextLines             = (defaults.object(forKey: "contextLines")         as? Int)  ?? 4
        largeFileThresholdMB     = (defaults.object(forKey: "largeFileThresholdMB") as? Int)  ?? 64
        recentRoots              = defaults.stringArray(forKey: "recentRoots") ?? []
    }

    func pushRecentRoot(_ path: String) {
        var list = recentRoots.filter { $0 != path }
        list.insert(path, at: 0)
        recentRoots = Array(list.prefix(10))
    }

    func clearRecentRoots() { recentRoots = [] }

    private static func detectTextEditor() -> String {
        let candidates = [
            "/Applications/BBEdit.app",
            "/Applications/Visual Studio Code.app",
            "/Applications/Sublime Text.app",
            "/Applications/Xcode.app",
            "/Applications/TextEdit.app",
        ]
        for c in candidates where FileManager.default.fileExists(atPath: c) {
            return c
        }
        return "/Applications/TextEdit.app"
    }

    /// Open `url` in the configured external editor. If `binary` is true,
    /// use the binary editor; otherwise the text editor.
    func openInExternalEditor(_ url: URL, binary: Bool = false) {
        let editor = binary ? binaryEditorPath : textEditorPath
        let editorURL = URL(fileURLWithPath: editor)
        let cfg = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.open([url], withApplicationAt: editorURL, configuration: cfg) { _, _ in }
    }
}
