import Foundation

/// One off-site (or any restic) replication target. The cloud layer is a **list** of these so
/// adding a backend later (Dropbox / Proton / S3 / rsync.net via restic's rclone backend) is
/// **config-only** — no engine changes. Each destination is independent and skip-if-unavailable.
///
/// Secrets never live in this struct or on disk in the clear — only the *name* of the macOS
/// Keychain service that holds them (`keychainService`). At runtime `ResticService` reads:
///   - account `restic-password`  → the repo passphrase (via `RESTIC_PASSWORD_COMMAND`)
///   - account `b2-account-id` / `b2-account-key`        (for `.resticB2`)
///   - account `rclone-config-path` / `rclone-config-pass` (for `.resticRclone`)
public struct CloudDestination: Codable, Sendable, Equatable, Identifiable {

    public enum Kind: String, Codable, Sendable {
        case resticB2        // restic native `b2:` backend (shipped)
        case resticRclone    // restic over an `rclone:` remote (Dropbox/Proton/S3/…) — future, config-only
    }

    public var id: UUID
    /// Human label shown in logs + PurpleMirror, e.g. "Backblaze B2".
    public var name: String
    public var kind: Kind
    public var enabled: Bool
    /// restic repository string. B2: `b2:<bucket>:<path>`. rclone: `rclone:<remote>:<path>`.
    public var repo: String
    /// `.resticRclone` only — the rclone remote name (informational; `repo` already encodes it).
    public var rcloneRemote: String?
    /// Keychain service name holding this destination's secrets (see type doc).
    public var keychainService: String
    /// Run `restic check` (structure) right after each backup. Deep `--read-data-subset` is a
    /// separate scheduled job.
    public var checkAfterBackup: Bool

    public init(id: UUID = UUID(), name: String, kind: Kind, enabled: Bool = true,
                repo: String, rcloneRemote: String? = nil, keychainService: String,
                checkAfterBackup: Bool = true) {
        self.id = id
        self.name = name
        self.kind = kind
        self.enabled = enabled
        self.repo = repo
        self.rcloneRemote = rcloneRemote
        self.keychainService = keychainService
        self.checkAfterBackup = checkAfterBackup
    }

    /// Resilient decode — every key `decodeIfPresent` with a default, same discipline as
    /// `ArchiveProfile`, so an older/partial profile.json never throws.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Cloud"
        kind = try c.decodeIfPresent(Kind.self, forKey: .kind) ?? .resticB2
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        repo = try c.decodeIfPresent(String.self, forKey: .repo) ?? ""
        rcloneRemote = try c.decodeIfPresent(String.self, forKey: .rcloneRemote)
        keychainService = try c.decodeIfPresent(String.self, forKey: .keychainService) ?? ""
        checkAfterBackup = try c.decodeIfPresent(Bool.self, forKey: .checkAfterBackup) ?? true
    }

    /// Minimal validity: a repo string and a Keychain service to read secrets from.
    public var isConfigured: Bool {
        !repo.trimmingCharacters(in: .whitespaces).isEmpty
            && !keychainService.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
