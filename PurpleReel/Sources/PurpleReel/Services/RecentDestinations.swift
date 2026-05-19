import Foundation

/// C22 — most-recently-used destination folder tracking for the
/// dialogs that ask for an output location (Convert, Combine, ...).
/// Mirrors the `RecentPresets` pattern in `TranscodePreset.swift`:
/// per-scope UserDefaults persistence, dedupe on push, cap at six so
/// the dropdown stays short.
///
/// Scopes are deliberately separate per dialog because the same user
/// often uses different destinations for different operations
/// (transcodes land in one folder, combined files in another). One
/// global recents list would force them to scroll past the wrong
/// scope's entries.
enum RecentDestinations {

    /// Scope keys — keep stable so persisted entries survive
    /// renames in the dialog code.
    enum Scope: String {
        case convert  = "recentDestinations.convert"
        case combine  = "recentDestinations.combine"
    }

    private static let cap = 6

    /// Returns the most-recent first.
    static func list(_ scope: Scope) -> [URL] {
        let raw = (UserDefaults.standard.array(forKey: scope.rawValue)
                    as? [String]) ?? []
        return raw.compactMap { path in
            let expanded = (path as NSString).expandingTildeInPath
            return URL(fileURLWithPath: expanded)
        }
    }

    /// Push a freshly-picked URL onto the recents list. Dedupes on
    /// path (case-sensitive — macOS HFS+ / APFS preserve case even
    /// though they're case-insensitive at lookup, so two paths that
    /// differ only in case still represent the same folder and the
    /// last-typed casing wins).
    static func push(_ url: URL, scope: Scope) {
        let path = url.path
        var current = (UserDefaults.standard.array(forKey: scope.rawValue)
                        as? [String]) ?? []
        // Case-insensitive dedupe — `URL.path` and the way Finder
        // emits paths can differ in trailing-slash treatment, so we
        // also normalize by stripping the trailing slash.
        let normalized = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        current.removeAll { existing in
            let e = existing.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return e.compare(normalized, options: .caseInsensitive) == .orderedSame
        }
        current.insert(path, at: 0)
        if current.count > cap { current = Array(current.prefix(cap)) }
        UserDefaults.standard.set(current, forKey: scope.rawValue)
    }

    /// Empties the recents list for a scope. No UI surfaces this yet
    /// — kept here so tests + a future "Clear recents" menu item can
    /// share the same path.
    static func clear(_ scope: Scope) {
        UserDefaults.standard.removeObject(forKey: scope.rawValue)
    }
}
