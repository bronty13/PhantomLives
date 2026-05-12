import Foundation
import CryptoKit

/// Common envelope format used by every persistent store (settings,
/// attachment file content). Layout is a 5-byte magic header followed by
/// an AES-GCM combined-format blob. Files written with `key == nil` come
/// out as raw bytes (plaintext); reads detect the format by checking for
/// the magic header so legacy plaintext files keep loading transparently.
///
/// Magic differs from PurpleIRC's "PIRC\x01" so a file can never be
/// misidentified across apps in the family.
enum EncryptedJSON {

    /// 5-byte file-format magic ("PLIF\x01"). Plaintext JSON starts with
    /// `{` / whitespace / alphabetic, so this sequence is unambiguous at
    /// load time. PNG starts with 0x89; JPEG starts with 0xFF; SQLite
    /// starts with "SQLite format". None collide.
    static let magic: [UInt8] = [0x50, 0x4C, 0x49, 0x46, 0x01]   // "PLIF\x01"

    enum EnvelopeError: Error {
        /// File on disk is encrypted but no DEK is available to read it.
        /// Caller usually treats this as "leave empty until keystore unlocks".
        case lockedButEncrypted
    }

    /// True when `data` starts with the magic header.
    static func hasMagic(_ data: Data) -> Bool {
        guard data.count >= magic.count else { return false }
        return Array(data.prefix(magic.count)) == magic
    }

    /// Wrap `plain` with the magic header + AES-GCM seal. `key == nil`
    /// returns the plain bytes unchanged so plaintext mode is a single
    /// branch in callers.
    static func wrap(_ plain: Data, key: SymmetricKey?) throws -> Data {
        guard let key else { return plain }
        let sealed = try Crypto.encrypt(plain, using: key)
        var out = Data(magic)
        out.append(sealed)
        return out
    }

    /// Inverse of `wrap`. Plaintext input (no magic) passes through
    /// untouched. An encrypted input without a key throws so the caller
    /// can decide how to surface "still locked" to the user.
    static func unwrap(_ file: Data, key: SymmetricKey?) throws -> Data {
        guard hasMagic(file) else { return file }
        guard let key else { throw EnvelopeError.lockedButEncrypted }
        let body = file.suffix(from: magic.count)
        return try Crypto.decrypt(Data(body), using: key)
    }

    /// Outcome of `safeWrite`. The `.skippedLockedEncrypted` case lets
    /// callers log / surface the protection without treating it as an error.
    enum SafeWriteResult {
        case wrote
        case skippedLockedEncrypted
    }

    /// Wrap `plain` and write it to `url`, **but refuse the write entirely
    /// when the file already on disk is encrypted and the caller hasn't
    /// supplied a key**. Without this guard, an early or stale save can
    /// silently clobber the user's encrypted data with plaintext defaults.
    /// Keeps the invariant: never downgrade an encrypted file to plaintext
    /// implicitly.
    @discardableResult
    static func safeWrite(_ plain: Data, to url: URL, key: SymmetricKey?) throws -> SafeWriteResult {
        if key == nil,
           let existing = try? Data(contentsOf: url),
           hasMagic(existing) {
            return .skippedLockedEncrypted
        }
        let bytes = try wrap(plain, key: key)
        try bytes.write(to: url, options: .atomic)
        // Tighten POSIX perms on the at-rest file to owner-only. The
        // contents are already sealed with AES-GCM when `key != nil`, but
        // restricting world/group read is cheap defence-in-depth and also
        // protects unencrypted-mode users (whose JSON would otherwise
        // inherit the user's umask, typically 0644).
        try? FileManager.default.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: url.path
        )
        return .wrote
    }
}
