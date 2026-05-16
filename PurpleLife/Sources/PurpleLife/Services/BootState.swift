import Foundation

/// Per-install "have we ever successfully launched?" marker. The file
/// lives at `<supportDir>/boot_state.json` and is written on every
/// successful launch (after the keystore is `.unlocked`). Its mere
/// existence is the load-bearing signal: it says "this install has
/// been used; data has been written under some DEK; do NOT generate a
/// fresh DEK here, because that would foreclose every recovery path
/// the user has left."
///
/// **Phase A.2 (2026-05-15)** — added in response to data-loss
/// incident #4. Without this marker, `KeyStore.setupKeychainManaged`
/// (when called against an empty Keychain slot) had no way to
/// distinguish "fresh install, safe to generate" from "Keychain entry
/// was destroyed out-of-band, generating now will lose the user's
/// data". The marker gives `setupKeychainManaged` the information it
/// needs to refuse: when the marker exists and the Keychain entry is
/// absent, the keystore throws `KeyStoreError.everBootedButKeychainGone`
/// and AppState routes to the recovery screen *without* creating a
/// fresh DEK — preserving Time Machine and (Phase B onward) the
/// user-held recovery key as live recovery paths.
///
/// **Reset behavior.** `DatabaseService.resetUnrecoverableDataAndReopen`
/// moves the marker file into the `.unrecoverable-<stamp>/`
/// quarantine alongside the rest of the support dir. After Reset the
/// next launch is correctly treated as fresh — the marker isn't
/// there, the bootstrap proceeds normally, the new DEK is generated.
/// This keeps Reset semantically clean: it's the user *choosing* to
/// abandon the encrypted data and start over.
struct BootState: Codable, Equatable {

    static let fileName = "boot_state.json"

    /// ISO-8601 timestamp of the very first successful launch on this
    /// install. Never overwritten after it's set, so support-dir
    /// forensics can always pin install age.
    let firstLaunchAt: String

    /// ISO-8601 timestamp of the most recent successful launch. Updated
    /// on every launch where the keystore reaches `.unlocked`.
    var lastLaunchAt: String

    /// Schema-version-style integer for future migrations of the marker
    /// payload itself. Increment if the JSON shape changes
    /// incompatibly; until then, every existing file stays decodable
    /// because `init(from:)` uses `decodeIfPresent` for every field.
    var version: Int = 1

    init(firstLaunchAt: String, lastLaunchAt: String, version: Int = 1) {
        self.firstLaunchAt = firstLaunchAt
        self.lastLaunchAt  = lastLaunchAt
        self.version       = version
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.firstLaunchAt = try c.decode(String.self, forKey: .firstLaunchAt)
        self.lastLaunchAt  = try c.decode(String.self, forKey: .lastLaunchAt)
        self.version       = try c.decodeIfPresent(Int.self, forKey: .version) ?? 1
    }

    // MARK: - File API

    static func markerURL(in supportDirectoryURL: URL) -> URL {
        supportDirectoryURL.appendingPathComponent(fileName)
    }

    /// True iff the marker file exists at the conventional path inside
    /// the support directory. Does NOT validate the file's contents —
    /// presence alone is the signal `setupKeychainManaged` needs. A
    /// corrupt or empty marker still counts as "ever booted" because
    /// the alternative (treat as fresh install) re-opens the data-
    /// loss trap.
    static func everBooted(in supportDirectoryURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: markerURL(in: supportDirectoryURL).path)
    }

    /// Write or update the marker. Called from `AppState` whenever the
    /// keystore reaches `.unlocked` (first launch and every launch
    /// thereafter). On the very first call, both timestamps are set
    /// to now; on subsequent calls, only `lastLaunchAt` advances.
    ///
    /// `nonisolated` so it can be invoked from any actor context —
    /// the body is purely file I/O with no actor-isolated state. The
    /// JSON write is best-effort: a failure here is a launch
    /// telemetry concern, not a correctness one. The app must launch
    /// even if the marker can't be written.
    nonisolated static func markBooted(in supportDirectoryURL: URL) {
        let now = ISO8601DateFormatter().string(from: Date())
        let url = markerURL(in: supportDirectoryURL)

        var state: BootState
        if let data = try? Data(contentsOf: url),
           let existing = try? JSONDecoder().decode(BootState.self, from: data) {
            state = existing
            state.lastLaunchAt = now
        } else {
            state = BootState(firstLaunchAt: now, lastLaunchAt: now)
        }

        do {
            try FileManager.default.createDirectory(
                at: supportDirectoryURL,
                withIntermediateDirectories: true
            )
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(state)
            try data.write(to: url, options: .atomic)
        } catch {
            NSLog("PurpleLife: BootState.markBooted failed — \(error.localizedDescription)")
        }
    }

    /// Read the marker if present. Returns nil for both "no file" and
    /// "file unreadable / undecodable" — callers wanting just the
    /// "ever booted" boolean should prefer `everBooted(in:)`.
    static func read(in supportDirectoryURL: URL) -> BootState? {
        guard let data = try? Data(contentsOf: markerURL(in: supportDirectoryURL)) else {
            return nil
        }
        return try? JSONDecoder().decode(BootState.self, from: data)
    }
}
