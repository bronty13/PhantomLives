import Foundation
import CryptoKit

/// Append-only persistent log writer. Files are laid out as
/// `<logsDir>/<networkSlug>/<bufferSlug>.log`. Each line is a timestamped
/// plain-text representation of a `ChatLine`, with mIRC codes stripped so the
/// file stays grep-friendly.
///
/// When a `currentKey` is set (ChatModel pushes in the KeyStore's DEK after
/// unlock), new lines are written as AES-GCM records in a binary envelope:
///
///     [5 bytes: "PLOG1"]
///     repeated:
///       [4 bytes big-endian uint32 length]
///       [length bytes: AES-GCM combined blob]
///
/// Previously-plaintext log files are rotated out to `<name>.log.plain` on
/// the first encrypted append so the user doesn't silently lose history.
/// Readers (RawLogView) transparently handle both formats.
///
/// Rotation is simple: when a file exceeds `rotateBytes` we rename it to
/// `.log.1` (overwriting any previous rotation).
///
/// The store is explicitly off the main actor so file IO doesn't stall the
/// UI. IRCConnection hands lines to it via a detached Task.
actor LogStore {
    private let baseURL: URL
    private let fm = FileManager.default
    private let rotateBytes: Int
    private static let iso: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// 5-byte file-format header used to distinguish encrypted logs from
    /// legacy plaintext. Plain files don't start with this sequence by
    /// chance — ISO-8601 timestamps start with a digit.
    static let encryptedMagic: [UInt8] = [0x50, 0x4C, 0x4F, 0x47, 0x01] // "PLOG\x01"

    /// Current data-encryption key. Nil → plain-text writes. Non-nil → AES-GCM
    /// wrapped lines with the header above.
    private var currentKey: SymmetricKey?

    init(baseURL: URL, rotateBytes: Int = 4 * 1024 * 1024) {
        self.baseURL = baseURL
        self.rotateBytes = rotateBytes
        try? fm.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }

    /// ChatModel pushes the DEK in whenever the KeyStore unlocks or locks.
    /// Passing nil (on lock) reverts future writes to plaintext.
    func setEncryptionKey(_ key: SymmetricKey?) {
        self.currentKey = key
    }

    /// Delete every log file under `baseURL` whose modification date is older
    /// than `days` days. Empty directories are pruned too so the Files menu
    /// doesn't show ghost folders. Returns the count of files removed so the
    /// caller can surface a summary if it likes.
    @discardableResult
    func purge(olderThanDays days: Int) -> Int {
        guard days > 0 else { return 0 }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        var removed = 0
        let enumerator = fm.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey])
            guard values?.isRegularFile == true,
                  let modDate = values?.contentModificationDate,
                  modDate < cutoff else { continue }
            do {
                try fm.removeItem(at: url)
                removed += 1
            } catch {
                NSLog("PurpleIRC: failed to purge \(url.lastPathComponent): \(error)")
            }
        }
        // Remove now-empty per-network directories so the Files menu stays clean.
        if let kids = try? fm.contentsOfDirectory(at: baseURL, includingPropertiesForKeys: nil) {
            for dir in kids where (try? dir.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                if let entries = try? fm.contentsOfDirectory(atPath: dir.path), entries.isEmpty {
                    try? fm.removeItem(at: dir)
                }
            }
        }
        return removed
    }

    func append(network: String, buffer: String, line: String) {
        let url = fileURL(network: network, buffer: buffer)
        do {
            try ensureParent(url: url)
            rotateIfNeeded(url: url)

            let record = "\(Self.iso.string(from: Date())) \(line)"

            if let key = currentKey {
                try appendEncrypted(record: record, key: key, to: url)
            } else {
                try appendPlain(record: record, to: url)
            }
        } catch {
            NSLog("PurpleIRC: log write failed for \(network)/\(buffer): \(error)")
        }
    }

    /// Returns the file contents as user-readable text. Encrypted records
    /// are decrypted on the fly; plain files pass through. Mixed-format
    /// files aren't possible — `appendEncrypted` rotates plaintext out
    /// before switching.
    func read(network: String, buffer: String) -> String? {
        let url = fileURL(network: network, buffer: buffer)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decodeFile(data: data)
    }

    func fileURL(network: String, buffer: String) -> URL {
        baseURL
            .appendingPathComponent(slug(network), isDirectory: true)
            .appendingPathComponent(slug(buffer) + ".log", isDirectory: false)
    }

    // MARK: - Write helpers

    private func appendPlain(record: String, to url: URL) throws {
        let data = Data((record + "\n").utf8)
        if fm.fileExists(atPath: url.path) {
            let handle = try FileHandle(forWritingTo: url)
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
            try handle.close()
        } else {
            try data.write(to: url, options: .atomic)
        }
    }

    private func appendEncrypted(record: String, key: SymmetricKey, to url: URL) throws {
        let sealed = try Crypto.encrypt(Data(record.utf8), using: key)
        var blob = Data()
        var length = UInt32(sealed.count).bigEndian
        withUnsafeBytes(of: &length) { blob.append(contentsOf: $0) }
        blob.append(sealed)

        if fm.fileExists(atPath: url.path) {
            let existing = try Data(contentsOf: url)
            if Self.hasEncryptedMagic(existing) {
                // Already an encrypted log — append the new record.
                let handle = try FileHandle(forWritingTo: url)
                try handle.seekToEnd()
                try handle.write(contentsOf: blob)
                try handle.close()
                return
            }
            // Plaintext file, but encryption is now on. Rotate the legacy
            // file out so it's preserved (user can still read or delete it
            // manually) and start a fresh encrypted file.
            let legacy = url.deletingPathExtension().appendingPathExtension("log.plain")
            try? fm.removeItem(at: legacy)
            try fm.moveItem(at: url, to: legacy)
        }
        // Create fresh file with the magic header + first record.
        var file = Data(Self.encryptedMagic)
        file.append(blob)
        try file.write(to: url, options: .atomic)
    }

    // MARK: - Read helpers

    private func decodeFile(data: Data) -> String? {
        if Self.hasEncryptedMagic(data) {
            return decodeEncryptedFile(data: data)
        }
        return String(data: data, encoding: .utf8)
    }

    private func decodeEncryptedFile(data: Data) -> String? {
        guard let key = currentKey else {
            return "(log is encrypted — unlock the keystore to read it)"
        }
        var cursor = Self.encryptedMagic.count
        var out = ""
        while cursor < data.count {
            // Need at least 4 bytes for length prefix; otherwise treat as
            // truncation and bail cleanly rather than throwing.
            guard cursor + 4 <= data.count else { break }
            let lenBytes = data[cursor..<cursor + 4]
            let len = Int(lenBytes.withUnsafeBytes { raw -> UInt32 in
                UInt32(bigEndian: raw.loadUnaligned(as: UInt32.self))
            })
            cursor += 4
            guard cursor + len <= data.count else { break }
            let slice = data[cursor..<cursor + len]
            cursor += len
            if let plain = try? Crypto.decrypt(Data(slice), using: key),
               let line = String(data: plain, encoding: .utf8) {
                out.append(line + "\n")
            } else {
                // Tamper / wrong key — record it and keep going so other
                // records in the same file are still recoverable.
                out.append("(corrupt or unreadable log record)\n")
            }
        }
        return out
    }

    private static func hasEncryptedMagic(_ data: Data) -> Bool {
        guard data.count >= encryptedMagic.count else { return false }
        return Array(data.prefix(encryptedMagic.count)) == encryptedMagic
    }

    // MARK: - Misc

    private func ensureParent(url: URL) throws {
        let parent = url.deletingLastPathComponent()
        if !fm.fileExists(atPath: parent.path) {
            try fm.createDirectory(at: parent, withIntermediateDirectories: true)
        }
    }

    private func rotateIfNeeded(url: URL) {
        guard let attrs = try? fm.attributesOfItem(atPath: url.path),
              let size = attrs[.size] as? NSNumber,
              size.intValue >= rotateBytes else { return }
        let rotated = url.appendingPathExtension("1")
        try? fm.removeItem(at: rotated)
        try? fm.moveItem(at: url, to: rotated)
    }

    /// Opaque filesystem slug derived from a SHA-256 of the lowercased
    /// original. Uses the first 16 hex chars (64 bits) — collision odds for
    /// a user's channel/nick count are astronomical. The point is that
    /// someone browsing the logs directory can no longer tell what channels
    /// or nicks the user has logged, which matches the rest of the
    /// encryption posture.
    ///
    /// Legacy plaintext slugs (pre-upgrade) are left on disk under their
    /// original names; new writes go to the hashed name. The purge sweep
    /// reaps stragglers over time.
    private func slug(_ s: String) -> String {
        let lower = s.lowercased()
        let digest = SHA256.hash(data: Data(lower.utf8))
        return digest.prefix(8).map { String(format: "%02x", $0) }.joined()
    }
}

extension ChatLine {
    /// Plain-text one-liner for persistent logs. No IRC codes, no SwiftUI
    /// styling — just a human-readable summary of the event. Used by the
    /// LogStore; not the right surface for bots (they want structured
    /// events via IRCConnectionEvent).
    func toLogLine() -> String {
        switch kind {
        case .info:           return "* \(text)"
        case .error:          return "! \(text)"
        case .motd:           return "MOTD \(text)"
        case .privmsg(let n, let isSelf):
            return "\(isSelf ? "→" : "<")\(n)\(isSelf ? "→" : ">") \(IRCFormatter.stripCodes(text))"
        case .action(let n):  return "* \(n) \(IRCFormatter.stripCodes(text))"
        case .notice(let f):  return "-\(f)- \(IRCFormatter.stripCodes(text))"
        case .join(let n):    return "→ \(n) joined"
        case .part(let n, let r):
            return "← \(n) left" + (r.map { " (\(IRCFormatter.stripCodes($0)))" } ?? "")
        case .quit(let n, let r):
            return "← \(n) quit" + (r.map { " (\(IRCFormatter.stripCodes($0)))" } ?? "")
        case .nick(let o, let nw):
            return "\(o) → \(nw)"
        case .topic(let setter):
            return (setter.map { "\($0) set topic: " } ?? "topic: ") + IRCFormatter.stripCodes(text)
        case .raw:            return text
        }
    }

    /// Not all lines are worth persisting. Server/MOTD numeric spam is noisy
    /// and usually skipped — toggleable via settings.
    var isNoisyLogKind: Bool {
        switch kind {
        case .motd, .info, .error: return true
        default: return false
        }
    }
}
