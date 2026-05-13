import Foundation
import SQLite3

/// One conversation partner enumerated from `chat.db`. The `handle` is
/// the raw identifier Messages uses (phone number in E.164 form or
/// email); we pass it verbatim to the CLI's `--handle` flag so there's
/// no fuzzy-match step that could pull in the wrong contact. The
/// optional `displayName` is filled in by `AddressBookLookup`; it stays
/// `nil` for handles that don't resolve (numbers from never-saved
/// contacts, business shortcodes, etc.).
struct Sender: Identifiable, Equatable, Hashable {
    /// Unique within a result set — the handle id itself doubles as the
    /// stable identifier. Two senders with the same handle are the same
    /// row even if their service / count drift between refreshes.
    var id: String { handle }

    var handle: String
    var service: String
    var messageCount: Int
    var lastMessageDate: Date?
    var displayName: String?
}

/// Read-only enumerator over `~/Library/Messages/chat.db` that returns
/// the list of 1:1 conversation partners (with per-handle message
/// count + last-message date for recency ranking). Pairs with
/// `AddressBookLookup` for optional display-name enrichment.
///
/// Uses the system `sqlite3` library (no SPM dependency) opened with
/// `mode=ro&immutable=1` so a running Messages.app holding the DB
/// doesn't block the read. Same pattern as `PurpleDedup`'s direct
/// `Photos.sqlite` reads — relies on the same FDA grant that the
/// existing chat.db preflight already requires.
enum SendersService {

    /// Default path to chat.db. Overridable so tests can pin a fixture
    /// file without monkey-patching environment.
    static var chatDBURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Messages/chat.db")
    }

    /// Enumerate every 1:1 sender from the given chat.db. Group chats
    /// (`chat.style == 43`, multi-member) are excluded for v1 — they
    /// need different CLI semantics (multiple handles per export) that
    /// the picker isn't ready to express. Returns the list sorted
    /// most-recent-first; ties broken by message count desc.
    ///
    /// Failures (DB missing, permission denied, schema drift) return an
    /// empty list + a short diagnostic — the caller surfaces it as a
    /// banner rather than crashing.
    static func enumerate(chatDB: URL = chatDBURL,
                          addressBook: [String: String] = [:])
                          -> (senders: [Sender], diagnostic: String?) {
        guard FileManager.default.fileExists(atPath: chatDB.path) else {
            return ([], "chat.db not found at \(chatDB.path)")
        }
        var db: OpaquePointer? = nil
        // immutable=1 skips locking — Messages.app holding the file
        // would otherwise EBUSY us out of an otherwise-fine read.
        let uri = "file:" + (chatDB.path as NSString)
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
            + "?mode=ro&immutable=1"
        let rc = sqlite3_open_v2(uri, &db,
                                 SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
        guard rc == SQLITE_OK, let db else {
            return ([], "chat.db open failed (\(rc))")
        }
        defer { sqlite3_close(db) }

        // GROUP BY h.id (not h.ROWID) collapses the "same number across
        // iMessage and SMS" case so the picker shows one row per
        // person, not one per service. We pick whichever service has
        // the most recent message to report — usually iMessage when
        // both exist, SMS when the contact has fallen off.
        //
        // The 1:1 filter is done at the chat level via the NOT EXISTS
        // probe: a chat with more than one distinct participant is a
        // group; we exclude it. This is more reliable than relying on
        // `chat.style`, whose values drift between macOS versions.
        let sql = """
        SELECT h.id AS handle,
               (SELECT h2.service FROM handle h2 WHERE h2.id = h.id
                ORDER BY h2.ROWID DESC LIMIT 1) AS service,
               COUNT(m.ROWID) AS msg_count,
               MAX(m.date)    AS last_date
        FROM message m
        JOIN handle h ON h.ROWID = m.handle_id
        WHERE m.handle_id IS NOT NULL
          AND EXISTS (
            SELECT 1 FROM chat_message_join cmj
            JOIN chat c ON c.ROWID = cmj.chat_id
            WHERE cmj.message_id = m.ROWID
              AND NOT EXISTS (
                SELECT 1 FROM chat_handle_join chj
                JOIN handle h2 ON h2.ROWID = chj.handle_id
                WHERE chj.chat_id = c.ROWID
                  AND h2.id <> h.id
              )
          )
        GROUP BY h.id
        ORDER BY last_date DESC, msg_count DESC
        """
        var stmt: OpaquePointer? = nil
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let stmt else {
            let err = String(cString: sqlite3_errmsg(db))
            return ([], "chat.db prepare failed: \(err)")
        }
        defer { sqlite3_finalize(stmt) }

        var out: [Sender] = []
        while sqlite3_step(stmt) == SQLITE_ROW {
            guard let handleC = sqlite3_column_text(stmt, 0) else { continue }
            let handle = String(cString: handleC)
            let service: String = {
                if let s = sqlite3_column_text(stmt, 1) {
                    return String(cString: s)
                }
                return "Unknown"
            }()
            let count = Int(sqlite3_column_int64(stmt, 2))
            let lastDate = macAbsoluteToDate(rawNs: sqlite3_column_int64(stmt, 3))
            let normalized = Self.normalize(handle: handle)
            out.append(Sender(
                handle: handle,
                service: service,
                messageCount: count,
                lastMessageDate: lastDate,
                displayName: addressBook[normalized]
            ))
        }
        return (out, nil)
    }

    /// chat.db on macOS 11+ stores `message.date` in nanoseconds since
    /// the 2001-01-01 UTC Mac epoch. Older releases used seconds; we
    /// fall back when the magnitude looks too small to be ns. Mirrors
    /// the `mts()` heuristic in `messages-exporter/export_messages.py`.
    private static let macEpochOffset: TimeInterval = 978307200  // 2001-01-01 UTC
    private static let nanosecondThreshold: Int64 = 10_000_000_000

    private static func macAbsoluteToDate(rawNs: Int64) -> Date? {
        guard rawNs > 0 else { return nil }
        let seconds: TimeInterval = rawNs > nanosecondThreshold
            ? TimeInterval(rawNs) / 1_000_000_000
            : TimeInterval(rawNs)
        return Date(timeIntervalSince1970: seconds + macEpochOffset)
    }

    /// Normalize a raw handle to the form `AddressBookLookup` keys with.
    /// Phone numbers → last 10 digits (matches the Python CLI's `norm`);
    /// emails → lowercased. Lets the picker resolve a US number stored
    /// as `+15551234567` to a contact entry written as `(555) 123-4567`.
    static func normalize(handle: String) -> String {
        if handle.contains("@") { return handle.lowercased() }
        let digits = handle.unicodeScalars.filter { CharacterSet.decimalDigits.contains($0) }
        let s = String(String.UnicodeScalarView(digits))
        return String(s.suffix(10))
    }
}
