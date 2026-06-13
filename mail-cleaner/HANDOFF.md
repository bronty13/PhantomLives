# mail-cleaner — HANDOFF

Canonical state snapshot for picking the mail-cleanup project back up. Last
updated **2026-06-13**. Tool version **0.3.0**.

`mail-cleaner/` is a stdlib-only Python IMAP triage/cleanup tool built to dig
Robert out of an overflowing mailbox. Apple Mail's `robert.olen@icloud.com`
(aliases `@me.com`/`@mac.com`) was receiving direct Gmail forwards from
`robert.olen@gmail.com` + `brontysore@gmail.com`, so the iCloud INBOX had
swollen to ~296k. Three mailboxes were cleaned: iCloud, then both Gmail
accounts.

---

## Current state (all three mailboxes)

| Mailbox | Key counts |
|---|---|
| **iCloud** `robert.olen@icloud.com` | INBOX **74,495** · Financial folder **32,059** · (was ~296k) |
| **Gmail** `robert.olen@gmail.com` | All Mail **175,031** · INBOX **171,749** · Trash **0** · (was 405,855) |
| **Gmail** `brontysore@gmail.com` | All Mail **715** · INBOX **698** · Trash **0** · (was 7,174) |

Everything below the "What's done" line is **complete and verified**. The
"Optional future passes" section is the only open work, and none of it is
urgent.

---

## What's done ✅

### iCloud (`robert.olen@icloud.com`)
- **Pass 1:** Nest (`notifications@nest.com`, 83,636 msgs/10.5 GB) + ~52 bulk
  senders permanently deleted (157,320 total). Financial (Amex/CapOne/banks/
  Experian/PayPal/M&T) archived to a **"Financial"** folder (28,544).
- **Pass 2 (2026-06-12):** re-analyzed the 110,143 remainder →
  - **Permanently deleted 32,134** — religious newsletters (Logos/FaithLife/
    Accordance — user chose *delete* this round) + long-tail commercial promos
    (social notifications, streaming, retail, MLM, travel rewards).
  - **Archived 3,515 more** financial (M&T/Citi/CapOne/Barclays/Discover) →
    Financial folder now **32,059**.
  - INBOX drained 110,143 → **74,495** (hit target exactly, single process).
- **App-specific password ROTATED** — the old one (`yjys-hbzb-nemk-mugi`, which
  had been pasted in chat) was revoked at appleid.apple.com → Sign-In &
  Security → App-Specific Passwords; a fresh one was generated and re-stored in
  Keychain. Login re-verified.

### Gmail `robert.olen@gmail.com` (the big one)
- Was 405,855 msgs / 28.9 GB. **Trashed 230,844** (Nest 93,261, Google Alerts
  30,641, religious, bulk promos) → All Mail 175,017.
- **Marked every message read.**
- **Global "forward a copy" DISABLED** + auto-delete filters created + account
  added to Apple Mail (user confirmed). This is the switch that stops the iCloud
  reflood — a filter's "Delete it" does *not* stop forwarding; the global toggle
  does.
- **KEPT:** financial (M&T/WF/CapOne/BofA/PayPal), Amazon receipts, Nikonians
  forum, directhomemedical. **TRASHED:** Logos/FaithLife religious.
- **Trash emptied permanently** (90,848 leftover → 0).

### Gmail `brontysore@gmail.com` (tiny)
- Was 7,174 msgs. **Trashed 6,466** (Apple/HP/Quora/Samsung/Adobe/Instagram
  newsletters + bardotbrush + Apple Card/Pay/Cash) → All Mail 708. No forwarding
  was ever configured on this account.
- **Trash emptied permanently** (6,466 → 0).

---

## How to run the tool

Stdlib only — no pip/venv. Python 3.9 (Command Line Tools) is fine.

```bash
cd ~/dev/PhantomLives/mail-cleaner

# read-only report -> ~/Downloads/mail-cleaner/<account>_<timestamp>/
python3 mailcleaner.py analyze --account icloud

# act on a reviewed sender allowlist (DRY-RUN by default)
python3 mailcleaner.py act --account icloud --action archive \
    --senders lists/icloud_financial_senders.txt --folder Financial

# permanent delete needs the explicit confirm token
python3 mailcleaner.py act --account icloud --action delete \
    --senders lists/icloud_pass2_delete_senders.txt --confirm DELETE
```

- `act` defaults to **dry-run**; nothing is touched without re-running. Permanent
  delete additionally requires `--confirm DELETE`.
- Client-side **exact `From:` verification** is on by default — guards against
  iCloud's loose token-based `SEARCH FROM` (it once returned two different Amex
  addresses as the same 9,840 hits).
- Gmail is auto-detected: default mailbox `[Gmail]/All Mail`, trash
  `[Gmail]/Trash`; the `delete` action is refused on Gmail (forced to trash, which
  is 30-day recoverable).

### Credentials (macOS Keychain)

| Account | Keychain service | login |
|---|---|---|
| iCloud | `mail-cleaner-icloud` | `robert.olen@icloud.com` |
| Gmail robert | `mail-cleaner-gmail-robert` | `robert.olen@gmail.com` |
| Gmail brontysore | `mail-cleaner-gmail-bronty` | `brontysore@gmail.com` |

Store/rotate any of them:
```bash
security add-generic-password -U -a "<login>" -s "<service>" -w "<app-password>"
```
Or pass `MAILCLEANER_PASSWORD=...` in the env for a one-off.

**App-password gotchas:** Gmail's are **16 lowercase letters** (Google shows them
with spaces — strip them). A pasted password can carry non-breaking-space
(`\xa0`) bytes, which makes `security -w` return the value as **hex** — decode hex
→ keep `a-z` → re-store clean. iCloud + Gmail both require 2FA / 2-Step
Verification on; Gmail app-passwords URL is `myaccount.google.com/apppasswords`.

---

## Hard-won IMAP quirks (read before a new pass)

**iCloud** (`imap.mail.me.com`)
- **No UIDPLUS, no MOVE.** Archive = COPY + `\Deleted` + EXPUNGE; delete = STORE
  `\Deleted` + EXPUNGE.
- **EXPUNGE is lazy/serialized:** only one runs at a time (a concurrent one
  returns `NO`), and it drains server-side over many minutes, throttled to
  ~2k/round. A purge of 150k+ takes hours but is reliable **single-process**.
- **`SEARCH DELETED` count is stale/unreliable** — always drive off
  `STATUS INBOX (MESSAGES)`.
- The tool's `expunge_until_drained()` re-issues EXPUNGE and polls MESSAGES until
  it reaches target or stalls. For a gentle standalone resume there's
  `/tmp/drain2.py` (single connection per round, hard FLOOR, one file-watching
  monitor) — recreate it if `/tmp` was cleared.

**Gmail** (`imap.gmail.com`)
- Labels, not folders; everything lives in `[Gmail]/All Mail`. IMAP "delete" only
  strips a label — real delete = move to `[Gmail]/Trash` (30-day recoverable),
  then empty Trash to make it permanent.
- Expunge is **fast and non-lazy** — but a **single EXPUNGE over ~90k messages
  trips a "System Error"** rate-limit abort. Use a **reconnect-and-retry expunge
  loop**: per round, re-`SEARCH ALL` + re-flag `\Deleted` + `expunge`, catching
  `imaplib.IMAP4.abort`; ~3–4 rounds clears 90k. (Same transient hit the
  mark-as-read pass — always wrap big Gmail batches in retry+reconnect.)
- The web "Empty Trash now" on a 230k trash drains **asynchronously** and can
  leave tens of thousands lingering for a while — finishing it over IMAP is
  faster and definitive.

**Hosting discipline (learned the hard way):** stacking multiple concurrent IMAP
processes (a drain + pollers + Monitors) **locked up the whole Mac** and needed a
reboot. Rule: **one IMAP process at a time, one connection per round, one
*file-watching* monitor (grep the output file — never a second live IMAP
poller).**

---

## Files

- `mailcleaner.py` — the tool (v0.2.1). `analyze` + `act` subcommands.
- `lists/` — reviewed sender allowlists (one address per line, `#` comments):
  - iCloud: `icloud_delete_senders.txt`, `icloud_financial_senders.txt`,
    `icloud_pass2_delete_senders.txt`, `icloud_pass2_financial_senders.txt`
  - Gmail: `gmail_delete_senders.txt`, `gmail_financial_senders.txt`,
    `gmail_robert_delete_senders.txt`, `gmail_brontysore_delete_senders.txt`
- `GMAIL_robert_forwarding_and_filters.md` — forwarding-off steps + paste-ready
  Gmail filter queries for the auto-delete senders.
- `README.md`, `CHANGELOG.md` — usage + history.
- Analyze reports land in `~/Downloads/mail-cleaner/<account>_<timestamp>/`
  (`report.txt`, `senders.csv` with List-Unsubscribe, `summary.json`).

---

## Unsubscribe (DONE 2026-06-13, now a built-in command)

A first unsubscribe sweep of the iCloud inbox's recurring promo senders was run:
**16 one-click POSTs (all HTTP 200) + 7 mailto unsubscribes sent**. These were
Gmail-list subscriptions (`se=robert.olen@gmail.com`) forwarding into iCloud, so
unsubscribing stops them at the Gmail source. Senders get up to ~10 business days
(CAN-SPAM) to comply — expect a short tail, then silence.

This was then **productionized into `mailcleaner.py unsubscribe`** (v0.3.0):
```bash
# dry-run (groups senders by method, sends nothing)
python3 mailcleaner.py unsubscribe --account icloud \
    --user robert.olen@icloud.com --keychain-service mail-cleaner-icloud \
    --senders lists/icloud_pass2_delete_senders.txt
# add --apply to fire one-click POSTs + mailto unsubs (logs to ~/Downloads/...)
```
It derives each sender's `List-Unsubscribe` link **live** from the newest message
(tokens rotate), fires one-click (RFC 8058 POST) + mailto (SMTP from the account),
and *reports-only* http-landing-page and no-header senders. Candidates via
`--senders` or `--from-csv <analyze senders.csv> --min-count N`. Run it for the
two Gmail accounts too when ready (`--account gmail`, their keychain services).

## Optional future passes (none urgent)

1. **Deeper iCloud tail** — the remaining 74,495 still has long-tail senders;
   re-`analyze` and triage another batch if the inbox still feels heavy.
2. **Unsubscribe the Gmail accounts** — the `unsubscribe` command now exists; run
   it against `robert.olen@gmail.com` + `brontysore@gmail.com` to cut their bulk
   senders at the source too.
3. **The 4 un-unsubscribable iCloud senders** — `microsoftstore@…` (89 msgs),
   `bardotbrush`, `sigsauer`, `redditmail` had no usable List-Unsubscribe hook;
   only levers are delete + a server-side rule.
4. **Trim Gmail All Mail** — 175k in robert's All Mail is mostly kept archive; a
   further pass could trash more bulk senders if desired.
5. **Going-forward Gmail filters** — beyond the current auto-delete set, add
   filters to auto-archive/label new mail so it doesn't re-accumulate.

When resuming: `git pull --rebase` from the repo root first, then re-`analyze`
the target account to get fresh counts before acting.
