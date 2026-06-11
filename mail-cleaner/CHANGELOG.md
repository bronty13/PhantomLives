# Changelog

## 0.2.1 — 2026-06-11

Cosmetic/correctness fixes found running the Gmail (brontysore) trash pass.

- Post-action drain target is now computed from the count captured **before**
  flagging, so it's correct on servers that auto-expunge `\Deleted` mid-loop
  (Gmail) — previously the target went negative and the drain idled ~2 min.
- Progress/summary text no longer hardcodes "iCloud" / "INBOX"; it names the
  actual mailbox acted on (e.g. `[Gmail]/All Mail`).

## 0.2.0 — 2026-06-11

Drain-aware expunge, hardened for iCloud's IMAP quirks (found while purging a
296k-message INBOX).

- **`expunge_until_drained`** — after flagging, re-issue `EXPUNGE` and poll the
  authoritative `STATUS (MESSAGES)` count until the purge actually completes,
  instead of firing one expunge and reporting "Done" while the server is still
  draining. Handles iCloud's serialized expunge (a concurrent one returns
  `NO`) by retrying, and ignores the unreliable/stale `SEARCH DELETED` count.
  Reports live `INBOX <count> (target ~<n>)` progress; gives up after ~2 min of
  no movement or a 90-min cap.
- `act` now prints the expected post-expunge count so deletes are verifiable.
- Note: iCloud advertises neither `UIDPLUS` nor `MOVE`, so `archive`/`trash`
  fall back to COPY + `\Deleted` + drain, and `delete` uses STORE + drain.

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
