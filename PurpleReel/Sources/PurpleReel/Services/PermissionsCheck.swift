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
/// We auto-probe four buckets:
/// - **Files & Folders → Movies** (default media location)
/// - **Files & Folders → Downloads** (PhantomLives default output)
/// - **Files & Folders → Documents** (where most users store edits)
/// - **Full Disk Access** (the catch-all; if granted, the three
///   above don't need individual grants either)
///
/// **Removable + Network Volumes are different on macOS 15+
/// (Sequoia / Tahoe).** They use a *consent-on-first-use* model:
/// the System Settings → Privacy & Security entry doesn't even
/// exist until the app has attempted to read from a real mount and
/// triggered a TCC prompt. There's no "Add app" affordance for the
/// user to grant proactively, and there's no static path we can
/// probe to detect prior grants. The wizard therefore offers
/// `triggerRemovableVolumePrompt` / `triggerNetworkVolumePrompt`
/// so users can fire the OS prompt on demand instead of waiting
/// until they happen to plug a drive in mid-edit.
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

    /// C31 — public probe used by the browser's permission-gotcha
    /// banner. Calls the same path-listing check the private helpers
    /// use; exposed so the banner can ask "is this specific folder
    /// readable?" against any user-selected workspace root.
    static func canRead(path: String) -> Bool {
        canRead(absolute: path)
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
    ///
    /// Note: on macOS 15+ the `Privacy_RemovableVolumes` and
    /// `Privacy_NetworkVolumes` URLs land on the generic Privacy
    /// pane because those sub-panes are not surfaced until an app
    /// has actually triggered a TCC prompt. Prefer
    /// `triggerRemovableVolumePrompt` / `triggerNetworkVolumePrompt`
    /// on Sequoia / Tahoe.
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

    // MARK: - Consent-on-first-use triggers (macOS 15+)

    /// Outcome of a manual trigger attempt.
    enum TriggerOutcome: Equatable {
        /// User cancelled the picker; no TCC prompt was issued.
        case cancelled
        /// Read succeeded — either the prompt fired and was allowed,
        /// or access was already granted from a prior session.
        case granted
        /// Read failed — the user denied the prompt, or the volume
        /// became unavailable mid-attempt. Includes the localized
        /// error description for diagnostics.
        case denied(reason: String)
    }

    /// Present an `NSOpenPanel` rooted at `/Volumes/` so the user can
    /// pick a mounted removable volume; then attempt a directory
    /// listing on the chosen folder. On macOS 15+ that read triggers
    /// the OS Allow/Deny dialog the first time PurpleReel touches a
    /// removable volume, which is the only way the System Settings
    /// → Privacy → Removable Volumes entry comes into existence.
    @MainActor
    static func triggerRemovableVolumePrompt() -> TriggerOutcome {
        let panel = NSOpenPanel()
        panel.title = "Pick a removable volume to grant access"
        panel.message = "Choose a USB stick, SD card, or camera-card mount under /Volumes/. PurpleReel will read the directory and macOS will prompt you to Allow access."
        panel.prompt = "Grant access"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return .cancelled }
        return attemptRead(at: url)
    }

    /// Open Finder's *Connect to Server* dialog so the user can mount
    /// an SMB / AFP / NFS share. After they mount one, the next time
    /// PurpleReel walks that share macOS will fire the Network
    /// Volumes prompt; this helper exists to get the user to that
    /// point in one click.
    @MainActor
    static func triggerNetworkVolumePrompt() -> TriggerOutcome {
        // Finder's Connect-to-Server panel is the canonical surface
        // for mounting a network share. We can't drive the mount
        // ourselves without an AppleEvents grant, so we hand off and
        // let the user pick a share to read against afterwards.
        if let url = URL(string: "smb://") {
            NSWorkspace.shared.open(url)
        }
        let panel = NSOpenPanel()
        panel.title = "After mounting, pick the share to grant access"
        panel.message = "Once your SMB / AFP / NFS share is mounted under /Volumes/, choose it here. PurpleReel will read the directory and macOS will prompt you to Allow access."
        panel.prompt = "Grant access"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.directoryURL = URL(fileURLWithPath: "/Volumes", isDirectory: true)
        let response = panel.runModal()
        guard response == .OK, let url = panel.url else { return .cancelled }
        return attemptRead(at: url)
    }

    /// Shared read-attempt used by the two trigger helpers and the
    /// PermissionsCheckTests suite. Returns `.granted` on a clean
    /// `contentsOfDirectory` call, `.denied` with the underlying
    /// error message otherwise.
    static func attemptRead(at url: URL) -> TriggerOutcome {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else {
            return .denied(reason: "Path no longer exists: \(url.path)")
        }
        do {
            _ = try fm.contentsOfDirectory(atPath: url.path)
            return .granted
        } catch {
            return .denied(reason: error.localizedDescription)
        }
    }
}
