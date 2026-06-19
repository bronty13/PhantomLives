import Foundation
import AppKit
import IRCKit

/// Plays CTCP SOUND clips. Sounds live in `~/Downloads/Ircle/Sounds/` (drop your
/// own `.wav`/`.aiff`/`.mp3` there). The incoming sound *name* is sanitized via
/// IRCKit's `DCC.sanitizeFilename` and resolved only within that folder, so a
/// remote peer can never make Ircle play (or probe) an arbitrary path.
@MainActor
final class SoundService {
    static let shared = SoundService()

    /// Mirrors `settings.ctcpSoundsEnabled`, kept in sync by the model.
    var enabled = true
    /// Where sound clips are read from. Overridable for tests.
    var directory: URL = SoundService.defaultDirectory

    static var defaultDirectory: URL {
        SettingsStore.downloadsDirectory.appendingPathComponent("Sounds", isDirectory: true)
    }

    /// Resolve a sound name to a playable file within the sounds folder, or nil
    /// if it doesn't exist. The name is sanitized first (no path escape).
    func soundURL(for name: String) -> URL? {
        let safe = DCC.sanitizeFilename(name)
        let url = directory.appendingPathComponent(safe)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// Play the named clip if sounds are enabled and the file exists. No-ops in
    /// non-app contexts (e.g. unit tests).
    func play(name: String) {
        guard enabled, Bundle.main.bundleIdentifier != nil, let url = soundURL(for: name) else { return }
        NSSound(contentsOf: url, byReference: true)?.play()
    }
}
