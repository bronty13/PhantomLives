# mail-cleaner

Bulk IMAP mailbox triage & cleanup for **iCloud** and **Gmail**. Stdlib-only
Python 3 — no `pip`, no venv. Built for mailboxes with *hundreds of thousands*
of messages, where Apple Mail / the web UI fall over.

Two commands:

- **`analyze`** — fully READ-ONLY. Connects, fetches only headers (never
  bodies), and writes a report of where the bulk lives: total count + size,
  top senders by count and size, counts by year, likely newsletters (have a
  `List-Unsubscribe` header), and the largest individual messages.
- **`act`** — delete / trash / archive messages, driven by an **explicit
  sender allowlist** (a text file you review). Defaults to a dry-run; needs
  `--apply` to touch anything, and `--confirm DELETE` for permanent deletes.
  There is deliberately **no** blanket "delete everything older than X" rule
  that could sweep up personal mail — you only ever act on senders you've
  approved.

## Safety model

- The only messages ever touched are those whose `From:` matches a sender on
  the list you pass with `--senders`.
- `act` is a **dry-run by default** — it prints exact per-sender counts and a
  total, and changes nothing. Add `--apply` to execute.
- `--action delete` is permanent (expunge). It additionally requires
  `--confirm DELETE`. Use `--action trash` (moves to Trash, recoverable
  ~30 days) or `--action archive --to <folder>` when you want reversibility.

## Credentials

Never on disk or the command line. The password is read from the macOS
Keychain (`--keychain-service`) or the `MAILCLEANER_PASSWORD` env var. iCloud
and Gmail both require an **app-specific password** (not your account
password) because of 2FA.

```sh
# one-time: store an app-specific password in the Keychain
security add-generic-password -a robert.olen@icloud.com -s mail-cleaner-icloud -w
```

## Usage

```sh
# 1. READ-ONLY analysis of every iCloud mailbox
python3 mailcleaner.py analyze --account icloud \
    --user robert.olen@icloud.com --keychain-service mail-cleaner-icloud \
    --all-mailboxes

# 2. Dry-run a delete plan against an approved sender list
python3 mailcleaner.py act --account icloud \
    --user robert.olen@icloud.com --keychain-service mail-cleaner-icloud \
    --senders lists/icloud_delete_senders.txt --action delete --mailbox INBOX

# 3. Execute it (permanent delete needs the explicit confirm token)
python3 mailcleaner.py act ... --action delete --apply --confirm DELETE

# Archive bank/card mail into a "Financial" folder instead of deleting
python3 mailcleaner.py act ... --senders lists/icloud_financial_senders.txt \
    --action archive --to Financial --apply
```

`--older-than YYYY-MM-DD` restricts any action to messages *before* a date.

## Output

Reports default to `~/Downloads/mail-cleaner/<account>_<timestamp>/`
(`report.txt`, `senders.csv`, `summary.json`). Override with `--out`.

## Accounts

Presets: `--account icloud` (`imap.mail.me.com`) and `--account gmail`
(`imap.gmail.com`). For any other server pass `--host` / `--port`. Gmail note:
Gmail "delete" via IMAP usually means *move to All Mail*; to truly trash,
move to `[Gmail]/Trash`. The `lists/` directory holds the reviewed sender
allowlists per account.
