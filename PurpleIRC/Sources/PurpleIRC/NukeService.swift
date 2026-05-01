import Foundation
import AppKit

/// `/nuke` — destructive reset of every piece of state PurpleIRC owns on
/// disk and in the Keychain. Designed for two scenarios:
///
///   1. Forgot-passphrase recovery (when the user is OK losing every
///      encrypted file rather than waiting on a futile passphrase guess).
///   2. Resetting a dev install for clean-room testing.
///
/// Wired to the slash command via `ChatModel.requestNuke()` which sets
/// `showNukeConfirmation`. The confirmation sheet lives in `ContentView`
/// and requires the user to type the literal phrase `NUKE` before the
/// destructive button enables. After execution the app is terminated;
/// the next launch comes up like a fresh install.
///
/// What gets wiped:
///
///   • The entire support directory (`~/Library/Application Support/PurpleIRC/`):
///     `settings.json`, `keystore.json`, `app.log`, `channels/*`,
///     `history/*`, `scripts/*`, `seen/*`, `logs/*`, `downloads/*`,
///     `backups/*` (when present).
///   • Every Keychain item under the `com.purpleirc` service (DEK cache,
///     SASL / NickServ / server / proxy passwords).
///   • The on-disk lastSession map inside settings.json (rendered moot by
///     deleting the file but called out for completeness).
///
/// What is NOT wiped:
///
///   • Per-app preferences in `~/Library/Preferences/com.example.PurpleIRC.plist`
///     (NSUserDefaults). PurpleIRC stores its own state in the support dir,
///     not in defaults — the plist would only carry SwiftUI's window-size
///     restoration data, which we don't consider "user data."
///
/// Safety rails:
///
///   • Always disconnects every live network first (graceful QUIT) so we
///     don't leave the user looking sane to channel ops while their local
///     state evaporates.
///   • Locks the keystore before touching the support directory so any
///     in-flight encrypted writes have a clean failure path.
///   • Best-effort `removeItem` on each subtree, not a recursive blast at
///     the support dir root, so we can log per-component results.
///   • Refuses to run if `supportDirectoryURL` looks suspicious (not under
///     `~/Library/Application Support` or path is empty). Belt-and-braces;
///     the URL comes from `FileManager` in production but the safety check
///     is cheap and prevents a pathological override from nuking elsewhere.
@MainActor
enum NukeService {

    /// One-shot destructive reset. Returns a `(removedPaths, errors)` tuple
    /// the caller can show to the user before terminating, so a failed
    /// nuke doesn't leave the user wondering what's left.
    @discardableResult
    static func performNuke(model: ChatModel) -> NukeResult {
        AppLog.shared.warn("NUKE invoked — destroying all on-disk state.",
                           category: "Nuke")

        // 1. Disconnect every live network with a recognizable QUIT reason
        //    so server-side observers see a clean exit, not a connection
        //    reset.
        for conn in model.connections {
            conn.disconnect(quitMessage: "PurpleIRC reset (NUKE)")
        }

        // 2. Lock the keystore. Any pending encrypted write that races us
        //    will hit `EncryptedJSON.safeWrite`'s skippedLockedEncrypted
        //    guard rather than producing a half-written file.
        model.keyStore.lock()

        let supportDir = model.settings.supportDirectoryURL
        let result = wipeSupportDirectory(supportDir)

        // 3. Wipe every Keychain item under our service. Idempotent.
        KeychainStore.deleteAll()
        AppLog.shared.warn("NUKE: cleared Keychain items under com.purpleirc.",
                           category: "Nuke")

        return result
    }

    /// Synchronous helper. Intentionally NOT recursive at the root — we
    /// remove the well-known component subdirectories one at a time so a
    /// pathological misconfiguration (e.g. supportDir pointing at $HOME)
    /// is bounded in blast radius. Even if a new subdirectory is added
    /// later, removing the named ones plus the canonical files clears
    /// everything PurpleIRC currently writes.
    private static func wipeSupportDirectory(_ supportDir: URL) -> NukeResult {
        var removed: [String] = []
        var errors: [String] = []

        // Sanity rail: the path must include "Application Support" or
        // ".config" — everything we ship writes under one of those, and a
        // mistaken absolute path elsewhere should refuse rather than
        // chew through the user's home directory.
        let path = supportDir.path
        let looksLegit = path.contains("Application Support")
            || path.contains(".config")
        guard looksLegit, !path.isEmpty else {
            errors.append("Refused to nuke suspicious support path: \(path)")
            AppLog.shared.error(
                "NUKE refused: supportDir does not look like an app-support path: \(path)",
                category: "Nuke")
            return NukeResult(removed: removed, errors: errors)
        }

        // Top-level files PurpleIRC writes directly under the support dir.
        let topLevelFiles = [
            "settings.json",
            "keystore.json",
            "app.log",
        ]

        // Subtrees PurpleIRC writes under the support dir.
        let subtrees = [
            "channels",
            "history",
            "scripts",
            "seen",
            "logs",
            "downloads",
            "backups",
            "blobs",       // forward-compat: future blob attachment store
            "photos",      // forward-compat: future address book photo store
        ]

        let fm = FileManager.default

        for name in topLevelFiles {
            let url = supportDir.appendingPathComponent(name)
            guard fm.fileExists(atPath: url.path) else { continue }
            do {
                try fm.removeItem(at: url)
                removed.append(name)
            } catch {
                errors.append("\(name): \(error.localizedDescription)")
            }
        }

        for name in subtrees {
            let url = supportDir.appendingPathComponent(name, isDirectory: true)
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            do {
                try fm.removeItem(at: url)
                removed.append("\(name)/")
            } catch {
                errors.append("\(name)/: \(error.localizedDescription)")
            }
        }

        AppLog.shared.warn(
            "NUKE: removed \(removed.count) item(s); \(errors.count) error(s).",
            category: "Nuke")
        return NukeResult(removed: removed, errors: errors)
    }

    /// Terminate the app cleanly so the next launch comes up fresh. Caller
    /// usually invokes this on a short delay so the confirmation sheet has
    /// time to dismiss and the AppLog write can flush.
    static func terminate(after seconds: TimeInterval = 0.5) {
        let ns = UInt64(seconds * 1_000_000_000)
        Task {
            try? await Task.sleep(nanoseconds: ns)
            await MainActor.run {
                NSApp.terminate(nil)
            }
        }
    }
}

struct NukeResult {
    let removed: [String]
    let errors: [String]

    var summary: String {
        if errors.isEmpty {
            return "Removed \(removed.count) item(s)."
        }
        return "Removed \(removed.count) item(s). \(errors.count) error(s):\n" +
            errors.joined(separator: "\n")
    }
}
