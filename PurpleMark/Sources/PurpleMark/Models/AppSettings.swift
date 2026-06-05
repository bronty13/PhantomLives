import SwiftUI
import Combine
import PurpleMarkRenderCore

/// A `UserDefaults`-backed value that publishes through its enclosing
/// `ObservableObject` — so settings persist across launches *and* drive SwiftUI
/// updates without per-property `didSet` boilerplate. Works for the primitive
/// types `UserDefaults` stores natively (Bool/Int/Double/String).
@propertyWrapper
struct Stored<Value> {
    let key: String
    let defaultValue: Value

    static subscript<T: ObservableObject>(
        _enclosingInstance instance: T,
        wrapped wrappedKeyPath: ReferenceWritableKeyPath<T, Value>,
        storage storageKeyPath: ReferenceWritableKeyPath<T, Self>
    ) -> Value where T.ObjectWillChangePublisher == ObservableObjectPublisher {
        get {
            let wrapper = instance[keyPath: storageKeyPath]
            return UserDefaults.standard.object(forKey: wrapper.key) as? Value
                ?? wrapper.defaultValue
        }
        set {
            let wrapper = instance[keyPath: storageKeyPath]
            instance.objectWillChange.send()
            UserDefaults.standard.set(newValue, forKey: wrapper.key)
        }
    }

    @available(*, unavailable, message: "Only usable on ObservableObject properties")
    var wrappedValue: Value {
        get { fatalError() }
        set { fatalError() }
    }
}

/// Which pane the single-pane editor is showing.
enum ViewMode: String { case document, markdown }

/// All user-configurable preferences (the OpenMark settings surface). Persisted
/// in `UserDefaults`; injected as an `@EnvironmentObject` and read by the
/// editor, the rendered preview, and the Settings window.
final class AppSettings: ObservableObject {
    static let shared = AppSettings()

    // General
    @Stored(key: "general.zenMode", defaultValue: false) var zenMode: Bool
    @Stored(key: "general.wordWrap", defaultValue: true) var wordWrap: Bool
    @Stored(key: "general.autoSave", defaultValue: true) var autoSave: Bool

    // Appearance
    @Stored(key: "appearance.theme", defaultValue: RenderTheme.default.rawValue) var themeRaw: String
    @Stored(key: "appearance.defaultView", defaultValue: ViewMode.document.rawValue) var defaultViewRaw: String
    @Stored(key: "appearance.readingWidth", defaultValue: ReadingWidth.default.rawValue) var readingWidthRaw: String
    @Stored(key: "appearance.editorContrast", defaultValue: true) var editorContrast: Bool

    // Editor
    @Stored(key: "editor.fontSize", defaultValue: 14.0) var fontSize: Double
    @Stored(key: "editor.fontName", defaultValue: "System Default") var editorFontName: String
    @Stored(key: "editor.showLineNumbers", defaultValue: true) var showLineNumbers: Bool
    @Stored(key: "editor.syncScroll", defaultValue: true) var syncScroll: Bool
    @Stored(key: "editor.autoCloseBrackets", defaultValue: true) var autoCloseBrackets: Bool
    @Stored(key: "editor.checkSpelling", defaultValue: true) var checkSpelling: Bool
    @Stored(key: "editor.tabWidth", defaultValue: 4) var tabWidth: Int

    // Writing
    @Stored(key: "writing.focusMode", defaultValue: false) var focusMode: Bool
    @Stored(key: "writing.typewriterMode", defaultValue: false) var typewriterMode: Bool

    // Export
    @Stored(key: "export.directoryPath", defaultValue: "") var exportDirectoryPath: String

    // Backup (launch-time auto-backup standard)
    @Stored(key: "backup.enabled", defaultValue: true) var autoBackupEnabled: Bool
    @Stored(key: "backup.retentionDays", defaultValue: 14) var backupRetentionDays: Int
    @Stored(key: "backup.directoryPath", defaultValue: "") var backupDirectoryPath: String
    @Stored(key: "backup.lastBackupAt", defaultValue: "") var lastBackupAt: String

    // MARK: Typed accessors

    var theme: RenderTheme {
        get { RenderTheme(rawValue: themeRaw) ?? .default }
        set { themeRaw = newValue.rawValue }
    }
    var defaultView: ViewMode {
        get { ViewMode(rawValue: defaultViewRaw) ?? .document }
        set { defaultViewRaw = newValue.rawValue }
    }
    var readingWidth: ReadingWidth {
        get { ReadingWidth(rawValue: readingWidthRaw) ?? .default }
        set { readingWidthRaw = newValue.rawValue }
    }

    /// The resolved editor font, honoring the "System Default" sentinel.
    func editorFont() -> NSFont {
        let size = CGFloat(fontSize)
        if editorFontName == "System Default" {
            return NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
        }
        return NSFont(name: editorFontName, size: size)
            ?? NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    /// Default export directory: `~/Downloads/PurpleMark/` unless overridden.
    var exportDirectory: URL {
        if !exportDirectoryPath.isEmpty {
            return URL(fileURLWithPath: exportDirectoryPath, isDirectory: true)
        }
        return FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Downloads/PurpleMark", isDirectory: true)
    }
}
