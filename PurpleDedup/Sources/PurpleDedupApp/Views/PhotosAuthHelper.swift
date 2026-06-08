import AppKit
import PurpleDedupCore

/// Shared PhotoKit-authorization side effects used by both the dedup flow
/// (`ContentView`) and the audit flow (`AuditView`). Centralised so the
/// `tccutil reset` recovery path and the Privacy-settings deep link exist in
/// exactly one place.
enum PhotosAuthHelper {
    /// Open System Settings → Privacy & Security → Photos.
    static func openPrivacySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Photos") {
            NSWorkspace.shared.open(url)
        }
    }

    /// Clear any stale TCC entry for Photos. This is the recovery path for a
    /// silent deny recorded before the entitlement existed, or after the user
    /// clicked "Don't Allow" and wants to be asked again.
    static func resetTCC() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tccutil")
        process.arguments = ["reset", "Photos", PurpleDedup.bundleIdentifier]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            Log.app.error("tccutil reset failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
