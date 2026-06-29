import Foundation

/// Configuration for the **ad-hoc Backblaze B2 file store** — a *second, separate* B2 account from
/// the photos off-site (`CloudDestination` / `ResticService`). Where the restic destination stores
/// the photo archive as opaque, deduplicated, encrypted packs (great for whole-tree snapshots, but
/// impossible to browse/rename/delete per file), this store is a **file-level rclone `crypt`
/// remote**: every object maps 1:1 to a real file PurpleAttic can list, rename, delete, diff, and
/// report on.
///
/// Like `CloudDestination`, secrets never live here or on disk in the clear — only the *name* of the
/// Keychain service that holds them (`keychainService`). At runtime `RcloneService` reads:
///   - account `b2-account-id` / `b2-account-key` → the second B2 account's application key
///   - account `crypt-password` (+ optional `crypt-password2` salt) → the rclone crypt passphrase,
///     stored in rclone's *obscured* form (see `RcloneService.obscure`)
///
/// The crypt passphrase is the **only key** to the data: lose it and the B2 objects are
/// unrecoverable. Setup (Phase 1) surfaces it once and forces a recovery-sheet save, mirroring the
/// restic recovery-key flow.
public struct AdhocBackupConfig: Codable, Sendable, Equatable, Identifiable {

    /// The Keychain service these secrets default to (a *different* service from the restic B2
    /// destination's "PurpleAttic Restic B2", so the two accounts never collide).
    public static let defaultKeychainService = "PurpleAttic B2 Ad-hoc"

    public var id: UUID
    /// Human label shown in the UI / logs, e.g. "Ad-hoc B2".
    public var name: String
    public var enabled: Bool
    /// The B2 bucket name for this ad-hoc account.
    public var bucket: String
    /// Optional path prefix *within* the bucket (e.g. "files"); empty = bucket root. Slashes are
    /// trimmed when composing the remote path so "/files/" and "files" behave identically.
    public var prefix: String
    /// Keychain service name holding this store's secrets (see type doc). Defaults to
    /// `defaultKeychainService`.
    public var keychainService: String
    /// Local files/folders this store backs up (one-way, additive). Order is preserved for the UI.
    public var sources: [String]
    /// Permanently delete (B2 `hard_delete`) instead of hiding. The maintainer chose
    /// **always-permanent**, so this defaults true; kept as a field for transparency/testability.
    public var hardDelete: Bool

    public init(id: UUID = UUID(),
                name: String = "Ad-hoc B2",
                enabled: Bool = true,
                bucket: String = "",
                prefix: String = "",
                keychainService: String = AdhocBackupConfig.defaultKeychainService,
                sources: [String] = [],
                hardDelete: Bool = true) {
        self.id = id
        self.name = name
        self.enabled = enabled
        self.bucket = bucket
        self.prefix = prefix
        self.keychainService = keychainService
        self.sources = sources
        self.hardDelete = hardDelete
    }

    /// Resilient decode — every key `decodeIfPresent` with a default, same discipline as
    /// `ArchiveProfile`/`CloudDestination`, so an older/partial profile.json never throws.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Ad-hoc B2"
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        bucket = try c.decodeIfPresent(String.self, forKey: .bucket) ?? ""
        prefix = try c.decodeIfPresent(String.self, forKey: .prefix) ?? ""
        keychainService = try c.decodeIfPresent(String.self, forKey: .keychainService)
            ?? AdhocBackupConfig.defaultKeychainService
        sources = try c.decodeIfPresent([String].self, forKey: .sources) ?? []
        hardDelete = try c.decodeIfPresent(Bool.self, forKey: .hardDelete) ?? true
    }

    /// Minimal validity: a bucket and a Keychain service to read secrets from.
    public var isConfigured: Bool {
        !bucket.trimmingCharacters(in: .whitespaces).isEmpty
            && !keychainService.trimmingCharacters(in: .whitespaces).isEmpty
    }
}
