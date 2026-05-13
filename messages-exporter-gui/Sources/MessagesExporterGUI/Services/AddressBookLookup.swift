import Foundation
import SQLite3

/// Reads macOS AddressBook source databases directly to build a
/// `[normalized-handle: displayName]` lookup. We deliberately avoid
/// `Contacts.framework` here — its TCC grant fights ad-hoc rebuilds,
/// silently no-ops `requestAccess` for untrusted bundles, and would
/// re-prompt users who already granted Full Disk Access. The abcddb
/// files sit under FDA, which the GUI already has.
///
/// Same approach as `messages-exporter/export_messages.py:get_handles()`
/// — that script walks the same files in Python under the same FDA
/// grant. This Swift reader runs the reverse direction (handle →
/// display name) so the sender picker can show "Alice Carter" next to
/// `+15551234567`.
enum AddressBookLookup {

    /// Default source directory. Each subdirectory is one AddressBook
    /// "source" (iCloud, local, Exchange, etc.) and contains a single
    /// `AddressBook-v22.abcddb` SQLite file. Overridable for tests.
    static var sourcesURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/AddressBook/Sources")
    }

    /// Walk every abcddb under `sourcesRoot` and return a map keyed by
    /// the normalized handle (`SendersService.normalize`). Best-effort:
    /// any open / schema failure on one source is logged via `NSLog`
    /// and the walk continues with the others. The returned diagnostic
    /// summarizes counts ("3 sources, 412 phone, 89 email") for the
    /// settings panel.
    static func buildLookup(sourcesRoot: URL = sourcesURL)
                            -> (map: [String: String], diagnostic: String) {
        var map: [String: String] = [:]
        var sourceCount = 0
        var phoneCount = 0
        var emailCount = 0

        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(at: sourcesRoot,
                                                       includingPropertiesForKeys: nil) else {
            return (map, "AddressBook sources unreadable at \(sourcesRoot.path)")
        }
        for sourceDir in entries {
            let dbURL = sourceDir.appendingPathComponent("AddressBook-v22.abcddb")
            guard fm.fileExists(atPath: dbURL.path) else { continue }
            sourceCount += 1
            let (added, addedP, addedE) = readSource(dbURL: dbURL, into: &map)
            // We deliberately add to the running totals only when the
            // open+query succeeded — readSource returns (0,0,0) on
            // failure with an NSLog'd reason.
            phoneCount += addedP
            emailCount += addedE
            _ = added
        }
        return (map, "AddressBook: \(sourceCount) source(s), "
                   + "\(phoneCount) phone, \(emailCount) email")
    }

    /// Read one source DB and merge its (handle → name) pairs into `map`.
    /// `map[key]` is set only if currently absent — first writer wins,
    /// which matches what the user sees in Contacts.app when sources
    /// disagree (iCloud entry takes priority over an older local copy
    /// when listed first in `Sources/`). Returns (rows, phones, emails).
    @discardableResult
    private static func readSource(dbURL: URL,
                                   into map: inout [String: String])
                                   -> (rows: Int, phones: Int, emails: Int) {
        var db: OpaquePointer? = nil
        let uri = "file:" + (dbURL.path as NSString)
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!
            + "?mode=ro&immutable=1"
        let rc = sqlite3_open_v2(uri, &db,
                                 SQLITE_OPEN_READONLY | SQLITE_OPEN_URI, nil)
        guard rc == SQLITE_OK, let db else {
            NSLog("AddressBookLookup: open failed for %@ rc=%d", dbURL.lastPathComponent, rc)
            return (0, 0, 0)
        }
        defer { sqlite3_close(db) }

        let displayNames = readDisplayNames(db: db)

        var phones = 0
        var emails = 0
        // Phone numbers: ZABCDPHONENUMBER.ZOWNER → ZABCDRECORD.Z_PK.
        let phoneSQL = """
        SELECT p.ZFULLNUMBER, p.ZOWNER
        FROM ZABCDPHONENUMBER p
        WHERE p.ZFULLNUMBER IS NOT NULL
        """
        forEachRow(db: db, sql: phoneSQL) { stmt in
            guard let raw = sqlite3_column_text(stmt, 0) else { return }
            let owner = Int(sqlite3_column_int64(stmt, 1))
            let phone = String(cString: raw)
            let key = SendersService.normalize(handle: phone)
            guard !key.isEmpty else { return }
            if map[key] == nil, let name = displayNames[owner] {
                map[key] = name
                phones += 1
            }
        }

        let emailSQL = """
        SELECT e.ZADDRESS, e.ZOWNER
        FROM ZABCDEMAILADDRESS e
        WHERE e.ZADDRESS IS NOT NULL
        """
        forEachRow(db: db, sql: emailSQL) { stmt in
            guard let raw = sqlite3_column_text(stmt, 0) else { return }
            let owner = Int(sqlite3_column_int64(stmt, 1))
            let addr = String(cString: raw).lowercased()
            if map[addr] == nil, let name = displayNames[owner] {
                map[addr] = name
                emails += 1
            }
        }

        return (phones + emails, phones, emails)
    }

    /// Build `Z_PK → "First Last"` (falls back to nickname / org).
    private static func readDisplayNames(db: OpaquePointer) -> [Int: String] {
        var out: [Int: String] = [:]
        let sql = """
        SELECT Z_PK, ZFIRSTNAME, ZLASTNAME, ZNICKNAME, ZORGANIZATION
        FROM ZABCDRECORD
        """
        forEachRow(db: db, sql: sql) { stmt in
            let pk = Int(sqlite3_column_int64(stmt, 0))
            let first = columnText(stmt, 1) ?? ""
            let last  = columnText(stmt, 2) ?? ""
            let nick  = columnText(stmt, 3) ?? ""
            let org   = columnText(stmt, 4) ?? ""
            let full = "\(first) \(last)".trimmingCharacters(in: .whitespaces)
            if !full.isEmpty {
                out[pk] = full
            } else if !nick.isEmpty {
                out[pk] = nick
            } else if !org.isEmpty {
                out[pk] = org
            }
        }
        return out
    }

    // MARK: - SQLite helpers

    private static func forEachRow(db: OpaquePointer, sql: String,
                                   _ body: (OpaquePointer) -> Void) {
        var stmt: OpaquePointer? = nil
        guard sqlite3_prepare_v2(db, sql, -1, &stmt, nil) == SQLITE_OK,
              let stmt else {
            NSLog("AddressBookLookup: prepare failed: %s",
                  sqlite3_errmsg(db))
            return
        }
        defer { sqlite3_finalize(stmt) }
        while sqlite3_step(stmt) == SQLITE_ROW {
            body(stmt)
        }
    }

    private static func columnText(_ stmt: OpaquePointer, _ idx: Int32) -> String? {
        guard let c = sqlite3_column_text(stmt, idx) else { return nil }
        let s = String(cString: c)
        return s.isEmpty ? nil : s
    }
}
