import Foundation
import IRCKit
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

    /// Persisted map of (network, buffer) name pairs that have ever been
    /// logged. The on-disk filenames are SHA-256 slugs to keep the directory
    /// opaque to disk browsers; this index is the only way to resolve a slug
    /// back to its friendly name once the buffer leaves memory. Sealed with
    /// the same DEK as the log files when one is set.
    struct LogIndex: Codable, Equatable {
        struct Entry: Codable, Equatable, Hashable {
            var network: String
            var buffer: String
        }
        var entries: [Entry] = []
    }

    /// In-memory index — backing for the on-disk `index.json`. Loaded
    /// lazily; flushed back to disk only when an `append` produces a new
    /// (network, buffer) pair that wasn't already there.
    private var index: LogIndex?
    private var indexLoaded: Bool = false

    init(baseURL: URL, rotateBytes: Int = 4 * 1024 * 1024) {
        self.baseURL = baseURL
        self.rotateBytes = rotateBytes
        try? fm.createDirectory(at: baseURL, withIntermediateDirectories: true)
    }

    /// Path of the index file relative to the logs root. Hidden behind a
    /// computed property so any future relocation flows through one place.
    private var indexURL: URL {
        baseURL.appendingPathComponent("index.json", isDirectory: false)
    }

    /// ChatModel pushes the DEK in whenever the KeyStore unlocks or locks.
    /// Passing nil (on lock) reverts future writes to plaintext.
    func setEncryptionKey(_ key: SymmetricKey?) {
        self.currentKey = key
    }

    /// Walk the logs directory, find every plaintext log file (`.log` files
    /// without the encrypted-magic header, plus any `.log.plain` rotation
    /// artifacts), re-encrypt their lines into the canonical encrypted file,
    /// and delete the plaintext source. Returns the count of files converted.
    /// Idempotent — already-encrypted files are skipped.
    @discardableResult
    func convertLegacyPlaintextLogs() -> Int {
        guard let key = currentKey else { return 0 }   // no key → nothing to migrate to
        var converted = 0
        let enumerator = fm.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let name = url.lastPathComponent
            // Only operate on log-shaped files. `.log.1` rotation files are
            // intentionally left alone — they belong to the rotation chain.
            guard name.hasSuffix(".log") || name.hasSuffix(".log.plain") else { continue }
            guard let raw = try? Data(contentsOf: url) else { continue }
            // Already encrypted? Skip.
            if Self.hasEncryptedMagic(raw) { continue }

            // Canonical target = same name, but with .plain stripped if present.
            // This way any "<network>/<buf>.log.plain" lands back in
            // "<network>/<buf>.log" alongside ongoing encrypted writes.
            let targetName: String
            if name.hasSuffix(".log.plain") {
                targetName = String(name.dropLast(".plain".count))
            } else {
                targetName = name   // self-replace
            }
            let target = url.deletingLastPathComponent().appendingPathComponent(targetName)

            // Read each line, encrypt as a record, write into the target.
            // Pre-existing encrypted target = append; otherwise create fresh.
            guard let plainText = String(data: raw, encoding: .utf8) else { continue }
            let lines = plainText.split(omittingEmptySubsequences: false, whereSeparator: { $0 == "\n" })
                .map(String.init)
                .filter { !$0.isEmpty }
            guard !lines.isEmpty else {
                try? fm.removeItem(at: url)
                converted += 1
                continue
            }
            do {
                for line in lines {
                    try appendEncrypted(record: line, key: key, to: target)
                }
                // Only remove the source after every record made it through.
                if url != target {
                    try? fm.removeItem(at: url)
                } else {
                    // Self-replace case — `appendEncrypted` already rewrote
                    // the file as encrypted, so the original plaintext
                    // contents are gone.
                }
                converted += 1
            } catch {
                NSLog("PurpleIRC: failed to convert \(name): \(error)")
            }
        }
        return converted
    }

    /// Count plaintext log files under `baseURL` so the UI can show the
    /// user how many will be converted before they confirm.
    func countLegacyPlaintextLogs() -> Int {
        var n = 0
        let enumerator = fm.enumerator(
            at: baseURL,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        )
        while let url = enumerator?.nextObject() as? URL {
            guard (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true else { continue }
            let name = url.lastPathComponent
            guard name.hasSuffix(".log") || name.hasSuffix(".log.plain") else { continue }
            if let raw = try? Data(contentsOf: url), !Self.hasEncryptedMagic(raw) {
                n += 1
            }
        }
        return n
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
            // Only purge log-shaped files. Without this guard a stale
            // `index.json` (or any other bookkeeping file) older than the
            // cutoff would be deleted, orphaning every log.
            let name = url.lastPathComponent
            guard name.hasSuffix(".log") || name.hasSuffix(".log.plain")
                    || name.hasSuffix(".log.1") else { continue }
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
            // Record the (network, buffer) pair so the chat-log viewer can
            // resolve slug filenames back to friendly names even when the
            // user isn't currently in that channel / connected to that
            // network. Cheap; we cache the in-memory map and only persist
            // when it changes shape.
            recordInIndex(network: network, buffer: buffer)
        } catch {
            NSLog("PurpleIRC: log write failed for \(network)/\(buffer): \(error)")
        }
    }

    /// Pair of (networkSlug, bufferSlug) for log files that are on disk but
    /// whose human names couldn't be resolved through the index. The viewer
    /// reads these via `readBySlug` so they're at least openable.
    struct OrphanLog: Hashable {
        var networkSlug: String
        var bufferSlug: String
    }

    /// Result of enumerating every browseable log on disk. Named entries
    /// come from the index (or a backfill); orphans are files whose
    /// network or buffer name was never recorded.
    struct EnumerationResult {
        var named: [LogIndex.Entry]
        var orphans: [OrphanLog]
    }

    /// Walk both the persistent index and the directory tree. Anything in
    /// the index OR matched by a backfilled name lands in `named`; anything
    /// else goes in `orphans` so the viewer can still open them.
    func enumerateAllLogs() -> EnumerationResult {
        loadIndexIfNeeded()
        let named = index?.entries ?? []

        // Build the set of (netSlug, bufSlug) pairs that the named index
        // already covers, so we know which on-disk files are "claimed."
        var claimedSlugs: Set<OrphanLog> = []
        for entry in named {
            claimedSlugs.insert(OrphanLog(
                networkSlug: slug(entry.network),
                bufferSlug: slug(entry.buffer)))
        }

        var orphans: [OrphanLog] = []
        guard let networkDirs = try? fm.contentsOfDirectory(
            at: baseURL, includingPropertiesForKeys: nil) else {
            return EnumerationResult(named: named.sorted {
                if $0.network != $1.network {
                    return $0.network.localizedCaseInsensitiveCompare($1.network) == .orderedAscending
                }
                return $0.buffer.localizedCaseInsensitiveCompare($1.buffer) == .orderedAscending
            }, orphans: [])
        }
        for netDir in networkDirs {
            var isDir: ObjCBool = false
            guard fm.fileExists(atPath: netDir.path, isDirectory: &isDir),
                  isDir.boolValue else { continue }
            guard let logs = try? fm.contentsOfDirectory(
                at: netDir, includingPropertiesForKeys: nil) else { continue }
            let netSlug = netDir.lastPathComponent
            for log in logs where log.pathExtension == "log" {
                let bufSlug = log.deletingPathExtension().lastPathComponent
                let pair = OrphanLog(networkSlug: netSlug, bufferSlug: bufSlug)
                if !claimedSlugs.contains(pair) {
                    orphans.append(pair)
                }
            }
        }

        return EnumerationResult(
            named: named.sorted {
                if $0.network != $1.network {
                    return $0.network.localizedCaseInsensitiveCompare($1.network) == .orderedAscending
                }
                return $0.buffer.localizedCaseInsensitiveCompare($1.buffer) == .orderedAscending
            },
            orphans: orphans.sorted {
                if $0.networkSlug != $1.networkSlug {
                    return $0.networkSlug < $1.networkSlug
                }
                return $0.bufferSlug < $1.bufferSlug
            }
        )
    }

    /// Older API — kept for backwards compatibility with anything that
    /// just wants the named list. New callers should prefer
    /// `enumerateAllLogs()` so they can also surface orphans.
    func enumerateIndex() -> [LogIndex.Entry] {
        enumerateAllLogs().named
    }

    /// One hit from `search(query:caseSensitive:limit:)`. Carries the
    /// raw line + the parsed ISO-8601 timestamp prefix so the UI can
    /// render relative times, plus network/buffer display names AND
    /// raw slugs so the click-to-jump path can route without
    /// re-hashing.
    struct SearchHit: Hashable, Identifiable {
        var id: String {
            "\(networkSlug)|\(bufferSlug)|\(lineNumber)"
        }
        let network: String
        let buffer: String
        let networkSlug: String
        let bufferSlug: String
        /// 1-based line number within the file. Useful for "result 1/N"
        /// affordances in the UI.
        let lineNumber: Int
        /// The full log-line text (including the ISO-8601 prefix).
        let line: String
        /// Parsed from the line's prefix when possible; nil for
        /// malformed lines (which shouldn't happen for files we wrote,
        /// but parser shouldn't panic on imports).
        let timestamp: Date?
        /// For fuzzy authored-by searches (`searchAuthored`): the actual
        /// author nick that matched the target (e.g. `johnny1` when the
        /// user searched `john_doe`). nil for plain substring `search`.
        var matchedNick: String? = nil
        /// Fuzzy similarity score `0...1` of `matchedNick` against the
        /// search target. 0 for plain substring `search`. Lets the
        /// authored-by UI rank the strongest variant matches first.
        var score: Double = 0
    }

    /// Scan every known log file for `query`. Walks both named-index
    /// entries and orphan slug files so freshly-restored backups (where
    /// the index hasn't been backfilled yet) still surface hits.
    ///
    /// Substring match against the textual content of each line (the
    /// ISO-8601 timestamp prefix is included in the scan — so a search
    /// for "2026-05" will match every line written this month, which
    /// is genuinely useful).
    ///
    /// `caseSensitive: false` lower-cases both needle and haystack via
    /// `String.range(of:options:)`. `limit` caps the result list so a
    /// pathologically broad query against a year of logs can't OOM the
    /// app — the UI surfaces "Showing first N of M+" when reached.
    ///
    /// Synchronous from the actor's perspective; reads + decrypts each
    /// log file in turn. Encrypted files go through `decodeFile` so
    /// the search transparently handles both formats.
    func search(query: String, caseSensitive: Bool = false, limit: Int = 500) -> [SearchHit] {
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !needle.isEmpty else { return [] }
        let options: String.CompareOptions = caseSensitive ? [] : [.caseInsensitive]
        var hits: [SearchHit] = []

        let result = enumerateAllLogs()
        // Named entries first — they have human display names for
        // network + buffer, which the result UI prefers to show.
        for entry in result.named {
            guard let text = read(network: entry.network, buffer: entry.buffer) else { continue }
            let netSlug = slug(entry.network)
            let bufSlug = slug(entry.buffer)
            scanText(text,
                     network: entry.network, buffer: entry.buffer,
                     networkSlug: netSlug, bufferSlug: bufSlug,
                     needle: needle, options: options,
                     hits: &hits, limit: limit)
            if hits.count >= limit { return hits }
        }
        // Orphans — slugs only. Surface them so a freshly-restored
        // backup that hasn't been backfilled still produces results.
        for orphan in result.orphans {
            guard let text = readBySlug(networkSlug: orphan.networkSlug,
                                         bufferSlug: orphan.bufferSlug) else { continue }
            scanText(text,
                     network: orphan.networkSlug,    // slug stands in for name
                     buffer: orphan.bufferSlug,
                     networkSlug: orphan.networkSlug,
                     bufferSlug: orphan.bufferSlug,
                     needle: needle, options: options,
                     hits: &hits, limit: limit)
            if hits.count >= limit { return hits }
        }
        return hits
    }

    /// Fuzzy "authored-by" search: every logged line whose *author* is the
    /// given `nick` or a variant of it (`john_doe` → `johndoe1`, `johnny1`,
    /// …). Unlike `search`, this parses the author token out of each line
    /// (via `NickFuzzyMatcher.authors`) and keeps the line only when an
    /// author fuzzily matches — so mention-only lines (someone else *talking
    /// about* the nick) are excluded.
    ///
    /// `threshold` is the fuzziness knob surfaced by the Find sheet's slider
    /// (lower = looser, more variants). Results come back sorted by descending
    /// match score, then most-recent-first, so the strongest variants lead.
    func searchAuthored(nick: String, threshold: Double, limit: Int = 500) -> [SearchHit] {
        let target = nick.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { return [] }
        var hits: [SearchHit] = []

        let result = enumerateAllLogs()
        for entry in result.named {
            guard let text = read(network: entry.network, buffer: entry.buffer) else { continue }
            scanAuthored(text,
                         network: entry.network, buffer: entry.buffer,
                         networkSlug: slug(entry.network), bufferSlug: slug(entry.buffer),
                         target: target, threshold: threshold, hits: &hits, limit: limit)
            if hits.count >= limit { break }
        }
        if hits.count < limit {
            for orphan in result.orphans {
                guard let text = readBySlug(networkSlug: orphan.networkSlug,
                                            bufferSlug: orphan.bufferSlug) else { continue }
                scanAuthored(text,
                             network: orphan.networkSlug, buffer: orphan.bufferSlug,
                             networkSlug: orphan.networkSlug, bufferSlug: orphan.bufferSlug,
                             target: target, threshold: threshold, hits: &hits, limit: limit)
                if hits.count >= limit { break }
            }
        }
        // Strongest variant matches first; break ties by recency so the most
        // useful lines are at the top of the Find sheet.
        return hits.sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return ($0.timestamp ?? .distantPast) > ($1.timestamp ?? .distantPast)
        }
    }

    /// Per-file worker for `searchAuthored`. Strips the timestamp prefix off
    /// each line, extracts the author nick(s), and keeps the line when one
    /// fuzzily matches the target. Records the matched variant + its score on
    /// the hit so the UI can show which nicks turned up and rank them.
    private func scanAuthored(_ text: String,
                              network: String, buffer: String,
                              networkSlug: String, bufferSlug: String,
                              target: String, threshold: Double,
                              hits: inout [SearchHit], limit: Int) {
        var lineNumber = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            lineNumber += 1
            let lineStr = String(line)
            // Body = everything after the leading ISO-8601 timestamp.
            let body: String
            if let sp = lineStr.firstIndex(of: " ") {
                body = String(lineStr[lineStr.index(after: sp)...])
            } else {
                body = lineStr
            }
            // Best (highest-scoring) matching author on this line, if any.
            var best: (nick: String, score: Double)? = nil
            for author in NickFuzzyMatcher.authors(ofLogLineBody: body) {
                guard NickFuzzyMatcher.matches(target: target, candidate: author,
                                               threshold: threshold) else { continue }
                let s = NickFuzzyMatcher.similarity(target, author)
                if best == nil || s > best!.score { best = (author, s) }
            }
            guard let match = best else { continue }
            hits.append(SearchHit(
                network: network,
                buffer: buffer,
                networkSlug: networkSlug,
                bufferSlug: bufferSlug,
                lineNumber: lineNumber,
                line: lineStr,
                timestamp: Self.parseLogTimestamp(lineStr),
                matchedNick: match.nick,
                score: match.score
            ))
            if hits.count >= limit { return }
        }
    }

    /// Per-file scan worker. Splits on newlines, runs the substring
    /// check, and parses the ISO-8601 prefix on each hit. Pulled out
    /// of `search` so the named+orphan paths share one definition.
    private func scanText(_ text: String,
                           network: String, buffer: String,
                           networkSlug: String, bufferSlug: String,
                           needle: String, options: String.CompareOptions,
                           hits: inout [SearchHit], limit: Int) {
        var lineNumber = 0
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            lineNumber += 1
            let lineStr = String(line)
            guard lineStr.range(of: needle, options: options) != nil else { continue }
            hits.append(SearchHit(
                network: network,
                buffer: buffer,
                networkSlug: networkSlug,
                bufferSlug: bufferSlug,
                lineNumber: lineNumber,
                line: lineStr,
                timestamp: Self.parseLogTimestamp(lineStr)
            ))
            if hits.count >= limit { return }
        }
    }

    /// Pull the leading ISO-8601 timestamp off a log line. Format
    /// matches what `LogStore.append` emits — see the `iso` formatter
    /// at the top of this file. Returns nil for lines that don't lead
    /// with a timestamp (shouldn't happen for files we wrote, but
    /// imports / hand-edits might).
    static func parseLogTimestamp(_ line: String) -> Date? {
        // Timestamps look like "2026-05-12T14:33:21.123Z " — find the
        // first space and parse everything before it.
        guard let sp = line.firstIndex(of: " ") else { return nil }
        let prefix = String(line[..<sp])
        return iso.date(from: prefix)
    }

    /// Add a (network, buffer) pair to the index if it isn't already there.
    /// Idempotent and cheap — only writes to disk when the in-memory set
    /// actually changed shape. Called from the `append` happy path.
    private func recordInIndex(network: String, buffer: String) {
        loadIndexIfNeeded()
        let entry = LogIndex.Entry(network: network, buffer: buffer)
        if index?.entries.contains(entry) == true { return }
        if index == nil { index = LogIndex() }
        index?.entries.append(entry)
        flushIndex()
    }

    /// Read the on-disk index into memory. Idempotent. Quietly returns an
    /// empty index if the file doesn't exist or can't be unwrapped.
    private func loadIndexIfNeeded() {
        guard !indexLoaded else { return }
        indexLoaded = true
        guard let data = try? Data(contentsOf: indexURL) else { return }
        guard let plain = try? EncryptedJSON.unwrap(data, key: currentKey) else { return }
        if let decoded = try? JSONDecoder().decode(LogIndex.self, from: plain) {
            index = decoded
        }
    }

    /// Persist the in-memory index. Errors are swallowed — the index is
    /// best-effort and a save failure shouldn't break logging.
    private func flushIndex() {
        guard let index else { return }
        guard let data = try? JSONEncoder().encode(index) else { return }
        _ = try? EncryptedJSON.safeWrite(data, to: indexURL, key: currentKey)
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

    /// Variant of `read` that takes the raw on-disk slug components. The
    /// slug function is one-way (SHA-256 hex), so for archive entries whose
    /// human names were never recorded we can't reconstruct them — but the
    /// slugs ARE the path. This lets the chat-log viewer open those
    /// orphaned files directly.
    func readBySlug(networkSlug: String, bufferSlug: String) -> String? {
        let url = baseURL
            .appendingPathComponent(networkSlug, isDirectory: true)
            .appendingPathComponent(bufferSlug + ".log", isDirectory: false)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return decodeFile(data: data)
    }

    /// Bulk record from outside — ChatModel calls this with every known
    /// (network, buffer) pair so the viewer can resolve slug filenames
    /// back to friendly names for buffers currently in memory plus
    /// anything in saved sessions. Idempotent; only persists if a new
    /// pair was added.
    func backfillIndex(_ pairs: [(network: String, buffer: String)]) {
        loadIndexIfNeeded()
        var added = false
        var current = Set(index?.entries ?? [])
        for pair in pairs {
            let entry = LogIndex.Entry(network: pair.network, buffer: pair.buffer)
            if current.insert(entry).inserted {
                if index == nil { index = LogIndex() }
                index?.entries.append(entry)
                added = true
            }
        }
        if added { flushIndex() }
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

    /// Best-effort reconstruction of a `ChatLine` from a persistent-log
    /// record (`"<ISO timestamp> <toLogLine output>"`), for seeding a freshly
    /// opened query buffer with scrollback. Logs are code-stripped text, so
    /// this is intentionally lossy: the two unambiguous, conversation-bearing
    /// shapes — `"<nick> text"` / `"→nick→ text"` (privmsg) and `"-nick- text"`
    /// (notice) — are reconstructed structurally so they render with proper
    /// nick styling; everything else (actions, joins/parts, topic changes,
    /// info) is shown verbatim as a `.raw` line, which reads correctly without
    /// risking a misparse. Returns nil for an empty/timestamp-less record.
    static func fromLogRecord(_ record: String) -> ChatLine? {
        guard let sp = record.firstIndex(of: " ") else { return nil }
        let ts = LogStore.parseLogTimestamp(record) ?? Date()
        let body = String(record[record.index(after: sp)...])
        guard !body.isEmpty else { return nil }

        // privmsg from someone else: "<nick> text"
        if body.hasPrefix("<"), let close = body.firstIndex(of: ">") {
            let nick = String(body[body.index(after: body.startIndex)..<close])
            if !nick.isEmpty {
                return ChatLine(timestamp: ts,
                                kind: .privmsg(nick: nick, isSelf: false),
                                text: trimmedRemainder(body, after: close))
            }
        }
        // our own privmsg: "→nick→ text" (join is "→ nick joined" — the space
        // after the arrow keeps the two apart).
        if body.hasPrefix("→"), !body.hasPrefix("→ ") {
            let afterFirst = body.index(after: body.startIndex)
            if let close = body[afterFirst...].firstIndex(of: "→") {
                let nick = String(body[afterFirst..<close])
                if !nick.isEmpty {
                    return ChatLine(timestamp: ts,
                                    kind: .privmsg(nick: nick, isSelf: true),
                                    text: trimmedRemainder(body, after: close))
                }
            }
        }
        // notice: "-nick- text"
        if body.hasPrefix("-") {
            let afterFirst = body.index(after: body.startIndex)
            if let close = body[afterFirst...].firstIndex(of: "-") {
                let nick = String(body[afterFirst..<close])
                if !nick.isEmpty, !nick.contains(" ") {
                    return ChatLine(timestamp: ts,
                                    kind: .notice(from: nick),
                                    text: trimmedRemainder(body, after: close))
                }
            }
        }
        // Actions, membership changes, topic, info — show the log line verbatim.
        return ChatLine(timestamp: ts, kind: .raw, text: body)
    }

    /// The substring after `idx`, with a single leading space dropped (the
    /// separator `toLogLine` inserts between the nick token and the message).
    private static func trimmedRemainder(_ s: String, after idx: String.Index) -> String {
        let start = s.index(after: idx)
        guard start < s.endIndex else { return "" }
        if s[start] == " " { return String(s[s.index(after: start)...]) }
        return String(s[start...])
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
