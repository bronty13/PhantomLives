# Changelog

## 0.1.0 — 2026-06-11

Initial release. Stdlib-only IMAP mailbox triage & cleanup for iCloud and Gmail.

- **`analyze`** — read-only mailbox report (totals, by-year, top senders by
  count and size, newsletters with `List-Unsubscribe`, largest messages).
  Header-only fetches; never reads bodies. Writes `report.txt`, `senders.csv`,
  `summary.json` to `~/Downloads/mail-cleaner/<account>_<timestamp>/`.
- **`act`** — delete / trash / archive driven by an explicit sender allowlist.
  Dry-run by default; `--apply` to execute; `--confirm DELETE` gate on
  permanent deletes; `--older-than YYYY-MM-DD` date restriction.
- **Client-side From verification** (default on for `act`): after the server
  `SEARCH FROM`, each candidate's `From:` header is re-fetched and only exact
  address matches are kept — guards against iCloud's loose token-based
  `SEARCH FROM` before an irreversible delete. `--no-verify` to skip.
- Credentials read from the macOS Keychain or `MAILCLEANER_PASSWORD`; never on
  disk or the command line.
- Raised `imaplib._MAXLINE` and added per-message fallback so a single
  oversized message can't abort a batch (real-world INBOX of 296k messages).
- Reviewed iCloud sender allowlists checked in under `lists/`.
