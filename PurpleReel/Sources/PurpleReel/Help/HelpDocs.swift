import Foundation
import AppKit

/// Resolves user-facing Markdown docs and opens them in the user's
/// default app. Priority order:
///   1. `Contents/Resources/Help/<name>.md` inside the running bundle
///      (ships with installed copies; works offline; pinned to the
///      binary version)
///   2. Sibling-of-binary path during development (xcodebuild puts the
///      .app in /tmp, so we walk up looking for a sibling repo)
///   3. The hard-coded repo path as a last-resort fallback for
///      developers running locally
///
/// If none resolves, a polite alert points the user at the
/// online reference.
enum HelpDocs {
    enum Document {
        case userManual
        case install
        case shortcutsMarkdown
        case kynoRoadmap

        /// File name (no extension) used to look up bundled resources.
        var resourceName: String {
            switch self {
            case .userManual:        return "USER_MANUAL"
            case .install:           return "INSTALL"
            case .shortcutsMarkdown: return "SHORTCUTS"
            case .kynoRoadmap:       return "KYNO_PARITY_ROADMAP"
            }
        }
        /// Title used in the missing-doc alert.
        var displayName: String {
            switch self {
            case .userManual:        return "User Manual"
            case .install:           return "Install & Setup"
            case .shortcutsMarkdown: return "Shortcuts Reference"
            case .kynoRoadmap:       return "Kyno Parity Roadmap"
            }
        }
    }

    /// Default entry point. Opens the doc in PurpleReel's in-app
    /// Markdown viewer (a free-floating WKWebView window backed by
    /// the bundled HTML rendition). Falls back to the legacy
    /// "open .md externally" path when the HTML isn't available —
    /// e.g. a developer running an unbundled debug build.
    static func open(_ doc: Document) {
        Task { @MainActor in
            MarkdownDocWindow.open(doc)
        }
    }

    /// Open the raw `.md` source via NSWorkspace — uses the system's
    /// default Markdown handler. Exposed because the in-app viewer's
    /// "Open .md…" affordance routes here, and as the fallback path
    /// when the HTML rendition can't be located.
    static func openExternally(_ doc: Document) {
        if let url = locateMarkdown(doc) {
            NSWorkspace.shared.open(url)
        } else {
            showMissingAlert(doc)
        }
    }

    // MARK: - Resolution

    /// Locate the source `.md` file. Public so the in-app viewer can
    /// reveal it in Finder and the `openExternally` path can hand it
    /// off to NSWorkspace.
    static func locateMarkdown(_ doc: Document) -> URL? {
        locate(doc)
    }

    private static func locate(_ doc: Document) -> URL? {
        // Bundled docs — try with and without the `Help` subdir
        // because xcodegen sometimes flattens nested resource dirs
        // depending on how the source path is declared.
        if let bundled = Bundle.main.url(forResource: doc.resourceName,
                                           withExtension: "md",
                                           subdirectory: "Help") {
            return bundled
        }
        if let bundled = Bundle.main.url(forResource: doc.resourceName,
                                           withExtension: "md") {
            return bundled
        }
        // Look one directory up from the .app for a sibling
        // PurpleReel project source — useful when the dev runs the
        // built `.app` directly out of the source tree.
        let bundlePath = Bundle.main.bundleURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(doc.resourceName).md")
        if FileManager.default.fileExists(atPath: bundlePath.path) {
            return bundlePath
        }
        // Last-resort dev fallback: the canonical project path.
        let dev = URL(fileURLWithPath:
            "\(NSHomeDirectory())/Documents/GitHub/PhantomLives/PurpleReel/\(doc.resourceName).md")
        if FileManager.default.fileExists(atPath: dev.path) {
            return dev
        }
        return nil
    }

    private static func showMissingAlert(_ doc: HelpDocs.Document) {
        let alert = NSAlert()
        alert.messageText = "\(doc.displayName) not found"
        alert.informativeText = """
            Could not locate \(doc.resourceName).md.

            The shipped app bundles its help docs in \
            Contents/Resources/Help/. Until that bundling step lands, \
            running PurpleReel from outside the source tree won't be \
            able to open this doc.
            """
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
}
