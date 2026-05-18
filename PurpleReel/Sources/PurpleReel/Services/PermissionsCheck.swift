import Foundation
import AppKit

/// macOS Privacy & Security permission detection for PurpleReel.
///
/// PurpleReel needs broad filesystem access — it browses arbitrary
/// user folders, mounted removable / network volumes, and (per the
/// Kyno-parity model) walks DCIM-style camera card structures on
/// mount. macOS gates all of that behind TCC, which Apple
/// deliberately doesn't expose a "do I have permission X" API for.
/// The standard workaround — and the one Kyno itself uses behind
/// the scenes — is to attempt a representative read on a path the
/// permission gates, and treat success as "granted".
///
/// We probe four buckets:
/// - **Files & Folders → Movies** (default media location)
/// - **Files & Folders → Downloads** (PhantomLives default output)
/// - **Files & Folders → Documents** (where most users store edits)
/// - **Full Disk Access** (the catch-all; if granted, the three
///   above don't need individual grants either)
///
/// Removable / network volumes are typically wide-open once the
/// user has authorized PurpleReel via "Removable Volumes" in the
/// Privacy pane, but there's no path we can statically test for
/// "is removable access granted" without an actual mount, so we
/// surface it as an informational item in the wizard rather than
/// a detected flag.
enum PermissionsCheck {
    struct Result: Equatable {
        var movies: Bool
        var downloads: Bool
        var documents: Bool
        var fullDiskAccess: Bool

        /// True when the user has at least enough to browse their own
        /// media folders. Full Disk Access trumps individual grants.
        var hasMinimumViable: Bool {
            fullDiskAccess || (movies && downloads && documents)
        }
    }

    static func run() -> Result {
        Result(
            movies:         canRead(home: "Movies"),
            downloads:      canRead(home: "Downloads"),
            documents:      canRead(home: "Documents"),
            fullDiskAccess: canRead(absolute: "/private/var/db")
        )
    }

    /// Attempt a directory listing under the user's home and return
    /// true if it succeeds. Empty result counts as success — the
    /// permission gate fires as a thrown error, not an empty list.
    private static func canRead(home component: String) -> Bool {
        let url = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent(component, isDirectory: true)
        return canRead(absolute: url.path)
    }

    private static func canRead(absolute path: String) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: path) else { return false }
        do {
            _ = try fm.contentsOfDirectory(atPath: path)
            return true
        } catch {
            return false
        }
    }

    /// Open System Settings → Privacy & Security to the requested
    /// sub-pane. Pane URLs are documented under
    /// `x-apple.systempreferences:com.apple.preference.security`.
    static func openSettings(_ pane: Pane) {
        let url = URL(string: pane.rawValue)!
        NSWorkspace.shared.open(url)
    }

    enum Pane: String, CaseIterable, Identifiable {
        case filesAndFolders = "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
        case fullDiskAccess  = "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
        case removableVolumes = "x-apple.systempreferences:com.apple.preference.security?Privacy_RemovableVolumes"
        case networkVolumes  = "x-apple.systempreferences:com.apple.preference.security?Privacy_NetworkVolumes"
        var id: String { rawValue }

        var label: String {
            switch self {
            case .filesAndFolders:  return "Files and Folders"
            case .fullDiskAccess:   return "Full Disk Access"
            case .removableVolumes: return "Removable Volumes"
            case .networkVolumes:   return "Network Volumes"
            }
        }
    }
}
