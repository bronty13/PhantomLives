#!/usr/bin/env python3
"""mail-cleaner — bulk IMAP mailbox triage & cleanup (iCloud + Gmail).

Stdlib only. No venv, no pip. Works against any IMAP server; presets exist
for iCloud (imap.mail.me.com) and Gmail (imap.gmail.com).

Phase 1 (this file): `analyze` — fully READ-ONLY. It connects, fetches only
headers (never message bodies), and writes a report so you can see where the
bulk lives before deleting anything. Later phases (plan/apply/unsubscribe)
build on the same connection layer.

Credentials never touch disk or the command line: the password is read from
the macOS Keychain (see --keychain-service) or the MAILCLEANER_PASSWORD env
var. For iCloud/Gmail with 2FA you must use an app-specific password.

Usage:
    # one-time: store an app-specific password in the Keychain
    security add-generic-password -a <user> -s mail-cleaner-icloud -w

    # read-only analysis of the iCloud inbox
    python3 mailcleaner.py analyze --account icloud \
        --user robert.olen@icloud.com --keychain-service mail-cleaner-icloud

    # analyze every mailbox, not just INBOX
    python3 mailcleaner.py analyze --account icloud --user <u> \
        --keychain-service mail-cleaner-icloud --all-mailboxes

Output: ~/Downloads/mail-cleaner/<account>_<timestamp>/
        report.txt, senders.csv, summary.json
"""

from __future__ import annotations

__version__ = "0.3.2"

import argparse
import csv
import imaplib
import json
import os
import re
import smtplib
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter, defaultdict
from datetime import datetime, timezone
from email.header import decode_header, make_header
from email.message import EmailMessage
from email.utils import parseaddr, parsedate_to_datetime
from pathlib import Path

# --- Account presets -------------------------------------------------------

PRESETS = {
    "icloud": {"host": "imap.mail.me.com", "port": 993},
    "gmail": {"host": "imap.gmail.com", "port": 993},
}

# SMTP presets for the mailto unsubscribe path (must send FROM the subscribed
# address for the unsubscribe to be honored). STARTTLS on 587.
SMTP_PRESETS = {
    "icloud": {"host": "smtp.mail.me.com", "port": 587},
    "gmail": {"host": "smtp.gmail.com", "port": 587},
}

# A browser-ish UA; some unsubscribe endpoints reject the default urllib one.
UNSUB_UA = "Mozilla/5.0 (mail-cleaner unsubscribe)"

# Header fields we pull for analysis. Bodies are never fetched.
HEADER_FIELDS = "FROM DATE SUBJECT LIST-UNSUBSCRIBE LIST-ID"
FETCH_ITEM = f"(RFC822.SIZE BODY.PEEK[HEADER.FIELDS ({HEADER_FIELDS})])"

DEFAULT_OUT = Path.home() / "Downloads" / "mail-cleaner"
BATCH = 200  # UIDs fetched per round-trip

# imaplib's default max line length (1 MB) chokes when a server packs a big
# FETCH response onto one line. Raise it generously.
imaplib._MAXLINE = 20_000_000

# Folders we never scan by default (trash/junk/spam), matched case-insensitively
# across iCloud, Gmail, and Exchange-style naming.
SKIP_MAILBOXES = {
    "deleted messages", "deleted items", "junk", "junk e-mail", "spam",
    "[gmail]/trash", "[gmail]/spam", "trash",
}


# --- Credentials -----------------------------------------------------------

def get_password(user: str, keychain_service: str | None) -> str:
    if os.environ.get("MAILCLEANER_PASSWORD"):
        return os.environ["MAILCLEANER_PASSWORD"]
    if keychain_service:
        try:
            out = subprocess.run(
                ["security", "find-generic-password",
                 "-a", user, "-s", keychain_service, "-w"],
                capture_output=True, text=True, check=True,
            )
            return out.stdout.strip()
        except subprocess.CalledProcessError:
            sys.exit(
                f"error: no Keychain item for account '{user}', service "
                f"'{keychain_service}'.\nStore one with:\n  security "
                f"add-generic-password -a {user} -s {keychain_service} -w"
            )
    sys.exit("error: set MAILCLEANER_PASSWORD or pass --keychain-service")


# --- IMAP helpers ----------------------------------------------------------

def connect(host: str, port: int, user: str, password: str) -> imaplib.IMAP4_SSL:
    M = imaplib.IMAP4_SSL(host, port)
    try:
        M.login(user, password)
    except imaplib.IMAP4.error as e:
        sys.exit(f"login failed: {e}\n(For iCloud/Gmail use an APP-SPECIFIC "
                 f"password, and the full address as the username.)")
    return M


def list_mailboxes(M: imaplib.IMAP4_SSL) -> list[str]:
    typ, data = M.list()
    boxes = []
    for raw in data or []:
        line = raw.decode(errors="replace") if isinstance(raw, bytes) else raw
        # format: (\HasNoChildren) "/" "INBOX"
        m = re.search(r' "(?:[^"]*)" "?([^"]*?)"?$', line)
        if m:
            boxes.append(m.group(1))
    return boxes


def decode_str(s: str | None) -> str:
    if not s:
        return ""
    try:
        return str(make_header(decode_header(s)))
    except Exception:
        return s


def parse_header_blob(blob: bytes) -> dict:
    """Parse the small header-fields blob into a dict."""
    text = blob.decode("utf-8", errors="replace")
    fields: dict[str, str] = {}
    cur_key = None
    for line in text.splitlines():
        if line and line[0] in " \t" and cur_key:  # folded continuation
            fields[cur_key] += " " + line.strip()
        elif ":" in line:
            k, _, v = line.partition(":")
            cur_key = k.strip().lower()
            fields[cur_key] = v.strip()
    return fields


# --- Analysis --------------------------------------------------------------

def year_bucket(date_hdr: str) -> str:
    try:
        dt = parsedate_to_datetime(date_hdr)
        if dt is None:
            return "unknown"
        return str(dt.year)
    except Exception:
        return "unknown"


def analyze_mailbox(M: imaplib.IMAP4_SSL, mailbox: str, agg: dict) -> int:
    typ, _ = M.select(f'"{mailbox}"', readonly=True)
    if typ != "OK":
        print(f"  ! could not open {mailbox}, skipping")
        return 0
    typ, data = M.uid("search", None, "ALL")
    if typ != "OK" or not data or not data[0]:
        return 0
    uids = data[0].split()
    total = len(uids)
    print(f"  {mailbox}: {total} messages")

    for i in range(0, total, BATCH):
        batch_uids = uids[i:i + BATCH]
        chunk = b",".join(batch_uids).decode()
        try:
            typ, resp = M.uid("fetch", chunk, FETCH_ITEM)
        except imaplib.IMAP4.error:
            # One oversized/odd message can blow up a whole batch — retry the
            # batch one UID at a time so we skip only the offender.
            resp = []
            for u in batch_uids:
                try:
                    t1, r1 = M.uid("fetch", u.decode(), FETCH_ITEM)
                    if t1 == "OK":
                        resp.extend(r1)
                except imaplib.IMAP4.error:
                    continue  # skip the single bad message
            typ = "OK"
        if typ != "OK":
            continue
        for item in resp:
            if not isinstance(item, tuple):
                continue
            meta = item[0].decode("utf-8", errors="replace")
            size_m = re.search(r"RFC822\.SIZE (\d+)", meta)
            size = int(size_m.group(1)) if size_m else 0
            hdrs = parse_header_blob(item[1])

            name, addr = parseaddr(hdrs.get("from", ""))
            addr = addr.lower()
            domain = addr.split("@")[-1] if "@" in addr else "(none)"
            yr = year_bucket(hdrs.get("date", ""))
            unsub = "list-unsubscribe" in hdrs or "list-id" in hdrs
            subject = decode_str(hdrs.get("subject", ""))

            agg["count"] += 1
            agg["bytes"] += size
            agg["by_year"][yr] += 1
            agg["sender_count"][addr or "(none)"] += 1
            agg["sender_bytes"][addr or "(none)"] += size
            agg["sender_name"].setdefault(addr or "(none)", decode_str(name))
            agg["domain_count"][domain] += 1
            if unsub:
                agg["newsletter_count"][addr or "(none)"] += 1
                agg["newsletter_unsub"][addr or "(none)"] = hdrs.get(
                    "list-unsubscribe", "")
            agg["largest"].append((size, addr, subject, mailbox))
        sys.stdout.write(f"\r  ...{min(i + BATCH, total)}/{total}")
        sys.stdout.flush()
    print()
    return total


def human(n: int) -> str:
    for unit in ("B", "KB", "MB", "GB", "TB"):
        if n < 1024:
            return f"{n:.1f}{unit}"
        n /= 1024
    return f"{n:.1f}PB"


def write_reports(account: str, agg: dict, out_dir: Path) -> None:
    out_dir.mkdir(parents=True, exist_ok=True)

    top_count = agg["sender_count"].most_common(50)
    top_bytes = sorted(agg["sender_bytes"].items(), key=lambda x: -x[1])[:50]
    top_domains = agg["domain_count"].most_common(30)
    newsletters = agg["newsletter_count"].most_common(50)
    largest = sorted(agg["largest"], reverse=True)[:50]

    # report.txt --------------------------------------------------------
    lines = []
    lines.append(f"mail-cleaner analysis — {account}")
    lines.append(f"generated {datetime.now().isoformat(timespec='seconds')}")
    lines.append("=" * 64)
    lines.append(f"Total messages : {agg['count']:,}")
    lines.append(f"Total size     : {human(agg['bytes'])}")
    lines.append("")
    lines.append("By year:")
    for yr in sorted(agg["by_year"], reverse=True):
        lines.append(f"  {yr:>8}  {agg['by_year'][yr]:>8,}")
    lines.append("")
    lines.append("Top 50 senders by message count:")
    for addr, c in top_count:
        nm = agg["sender_name"].get(addr, "")
        lines.append(f"  {c:>7,}  {addr}  {('('+nm+')') if nm else ''}")
    lines.append("")
    lines.append("Top 50 senders by total size:")
    for addr, b in top_bytes:
        lines.append(f"  {human(b):>9}  {addr}")
    lines.append("")
    lines.append("Top 30 sender domains:")
    for dom, c in top_domains:
        lines.append(f"  {c:>7,}  {dom}")
    lines.append("")
    lines.append("Likely newsletters / bulk (have List-Unsubscribe), top 50:")
    for addr, c in newsletters:
        lines.append(f"  {c:>7,}  {addr}")
    lines.append("")
    lines.append("50 largest individual messages:")
    for size, addr, subj, box in largest:
        lines.append(f"  {human(size):>9}  {addr:40.40}  {subj:50.50}  [{box}]")
    report = "\n".join(lines)
    (out_dir / "report.txt").write_text(report)

    # senders.csv -------------------------------------------------------
    with (out_dir / "senders.csv").open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["address", "name", "count", "total_bytes",
                    "is_newsletter", "unsubscribe"])
        for addr in sorted(agg["sender_count"],
                           key=lambda a: -agg["sender_count"][a]):
            w.writerow([
                addr,
                agg["sender_name"].get(addr, ""),
                agg["sender_count"][addr],
                agg["sender_bytes"][addr],
                "yes" if addr in agg["newsletter_count"] else "",
                agg["newsletter_unsub"].get(addr, ""),
            ])

    # summary.json ------------------------------------------------------
    summary = {
        "account": account,
        "generated": datetime.now(timezone.utc).isoformat(),
        "total_messages": agg["count"],
        "total_bytes": agg["bytes"],
        "by_year": dict(agg["by_year"]),
        "top_senders_by_count": top_count,
        "top_senders_by_bytes": top_bytes,
        "top_domains": top_domains,
        "newsletters": newsletters,
    }
    (out_dir / "summary.json").write_text(json.dumps(summary, indent=2))

    print("\n" + report[:2000])
    print(f"\nFull report written to: {out_dir}")


def cmd_analyze(args: argparse.Namespace) -> None:
    preset = PRESETS.get(args.account, {})
    host = args.host or preset.get("host")
    port = args.port or preset.get("port", 993)
    if not host:
        sys.exit("error: --host required (or use --account icloud|gmail)")

    password = get_password(args.user, args.keychain_service)
    M = connect(host, port, args.user, password)
    print(f"connected to {host} as {args.user}")

    if args.all_mailboxes:
        mailboxes = list_mailboxes(M)
        # skip Trash/Junk by default unless asked
        mailboxes = [b for b in mailboxes if b.lower() not in SKIP_MAILBOXES]
    else:
        # Gmail stores every message in "[Gmail]/All Mail"; scanning each
        # label instead would double-count messages that carry several labels.
        default_box = "[Gmail]/All Mail" if args.account == "gmail" else "INBOX"
        mailboxes = args.mailbox or [default_box]

    print(f"scanning {len(mailboxes)} mailbox(es): {', '.join(mailboxes)}")

    agg = {
        "count": 0, "bytes": 0,
        "by_year": Counter(),
        "sender_count": Counter(), "sender_bytes": Counter(),
        "sender_name": {}, "domain_count": Counter(),
        "newsletter_count": Counter(), "newsletter_unsub": {},
        "largest": [],
    }
    for box in mailboxes:
        analyze_mailbox(M, box, agg)
        # keep memory bounded: trim largest list periodically
        agg["largest"] = sorted(agg["largest"], reverse=True)[:200]

    try:
        M.logout()
    except Exception:
        pass

    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = (Path(args.out) if args.out else DEFAULT_OUT) / f"{args.account}_{stamp}"
    write_reports(args.account, agg, out_dir)


MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun",
          "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]


def imap_date(iso: str) -> str:
    """YYYY-MM-DD -> DD-Mon-YYYY for IMAP SEARCH."""
    dt = datetime.strptime(iso, "%Y-%m-%d")
    return f"{dt.day:02d}-{MONTHS[dt.month - 1]}-{dt.year}"


def load_senders(path: str) -> list[str]:
    senders = []
    for line in Path(path).read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        senders.append(line)
    return senders


def search_sender(M: imaplib.IMAP4_SSL, sender: str,
                  before: str | None) -> list[bytes]:
    crit = ["FROM", f'"{sender}"']
    if before:
        crit += ["BEFORE", imap_date(before)]
    typ, data = M.uid("search", None, *crit)
    if typ != "OK" or not data or not data[0]:
        return []
    return data[0].split()


def chunked(seq, n):
    for i in range(0, len(seq), n):
        yield seq[i:i + n]


def mailbox_count(M: imaplib.IMAP4_SSL, mailbox: str) -> int:
    typ, d = M.status(f'"{mailbox}"', "(MESSAGES)")
    if typ != "OK" or not d or not d[0]:
        return -1
    m = re.search(rb"MESSAGES (\d+)", d[0])
    return int(m.group(1)) if m else -1


def expunge_until_drained(M: imaplib.IMAP4_SSL, mailbox: str, target: int,
                          label: str, time_cap: int = 5400) -> int:
    """Issue EXPUNGE and poll MESSAGES until it reaches ~target.

    iCloud has quirks worth handling explicitly: EXPUNGE is serialized (a
    second concurrent one returns 'NO') and processed lazily over many
    minutes, and SEARCH DELETED returns a stale count. So we never trust a
    single EXPUNGE return or the DELETED count — we re-issue EXPUNGE and drive
    off the authoritative MESSAGES count until it stops dropping or hits the
    target."""
    deadline = time.time() + time_cap
    last = None
    stalled = 0
    while time.time() < deadline:
        try:
            M.expunge()
        except imaplib.IMAP4.error:
            pass  # 'NO' — another expunge in progress; wait and re-poll
        cnt = mailbox_count(M, mailbox)
        sys.stdout.write(
            f"\r  {label} expunge: {mailbox} {cnt:,} (target ~{target:,})    ")
        sys.stdout.flush()
        if cnt <= target:
            break
        stalled = stalled + 1 if cnt == last else 0
        if stalled >= 12:  # ~2 min of no movement -> stop waiting
            break
        last = cnt
        time.sleep(10)
    print()
    return mailbox_count(M, mailbox)


def verify_from(M: imaplib.IMAP4_SSL, uids: list[bytes],
                want: str) -> list[bytes]:
    """Re-fetch the From header for each uid and keep only those whose parsed
    address equals `want` exactly (case-insensitive). Guards against loose
    server-side SEARCH FROM matching before an irreversible delete."""
    want = want.lower()
    kept = []
    for batch in chunked(uids, 500):
        ids = b",".join(batch).decode()
        typ, resp = M.uid("fetch", ids,
                          "(BODY.PEEK[HEADER.FIELDS (FROM)])")
        if typ != "OK":
            continue
        for item in resp:
            if not isinstance(item, tuple):
                continue
            uid_m = re.search(rb"UID (\d+)", item[0])
            if not uid_m:
                continue
            uid = uid_m.group(1)
            hdrs = parse_header_blob(item[1])
            _, addr = parseaddr(hdrs.get("from", ""))
            if addr.lower() == want:
                kept.append(uid)
    return kept


def copy_verified(M: imaplib.IMAP4_SSL, ids: str, dest: str) -> bool:
    """COPY a batch to `dest` and confirm the server accepted it.

    CRITICAL for archive/trash on servers without MOVE (iCloud): the caller
    must NOT flag the originals \\Deleted unless the copy actually succeeded,
    or a transient COPY failure silently destroys mail (it gets expunged from
    the source but never lands in the destination). iCloud lacks UIDPLUS, so we
    can't match COPYUID; we treat an OK tagged response as success and any
    NO/BAD/exception as failure. Returns True only on a confirmed copy."""
    try:
        typ, _ = M.uid("COPY", ids, f'"{dest}"')
        return typ == "OK"
    except imaplib.IMAP4.error:
        return False


def cmd_act(args: argparse.Namespace) -> None:
    preset = PRESETS.get(args.account, {})
    host = args.host or preset.get("host")
    port = args.port or preset.get("port", 993)
    if not host:
        sys.exit("error: --host required (or use --account icloud|gmail)")

    senders = load_senders(args.senders)
    if not senders:
        sys.exit(f"error: no senders in {args.senders}")

    # Gmail-aware defaults: act on All Mail (where every message lives) and
    # "delete" by moving to [Gmail]/Trash (Google purges it after 30 days).
    is_gmail = args.account == "gmail"
    if args.mailbox is None:
        args.mailbox = "[Gmail]/All Mail" if is_gmail else "INBOX"
    if args.trash_folder is None:
        args.trash_folder = "[Gmail]/Trash" if is_gmail else "Deleted Items"
    if is_gmail and args.action == "delete":
        sys.exit("error: on Gmail, IMAP 'delete' only strips a label (the "
                 "message survives in All Mail). Use --action trash "
                 "(--trash-folder defaults to [Gmail]/Trash, 30-day "
                 "recoverable) to actually remove messages.")

    password = get_password(args.user, args.keychain_service)
    M = connect(host, port, args.user, password)
    caps = " ".join(c.decode() if isinstance(c, bytes) else c
                    for c in (M.capabilities or ()))
    have_move = "MOVE" in caps
    have_uidplus = "UIDPLUS" in caps
    print(f"connected to {host} as {args.user}")
    print(f"action={args.action}  mailbox={args.mailbox}  "
          f"senders={len(senders)}  "
          f"{'older-than ' + args.older_than if args.older_than else 'all dates'}")

    M.select(f'"{args.mailbox}"')  # read-write

    if args.action == "archive":
        # ensure destination exists (ignore 'already exists')
        M.create(f'"{args.to}"')

    # --- gather matches per sender (always; this is the dry-run report) ---
    verify = not args.no_verify
    if verify:
        print("(verifying exact From: address client-side — slower, safer)")
    per_sender = []
    all_uids: list[bytes] = []
    for s in senders:
        uids = search_sender(M, s, args.older_than)
        if verify and uids:
            uids = verify_from(M, uids, s)
        per_sender.append((s, len(uids)))
        all_uids.extend(uids)
    # de-dup UIDs (a message matching two senders is impossible, but be safe)
    all_uids = list(dict.fromkeys(all_uids))

    per_sender.sort(key=lambda x: -x[1])
    print("\nMatches per sender:")
    for s, c in per_sender:
        if c:
            print(f"  {c:>8,}  {s}")
    zero = [s for s, c in per_sender if c == 0]
    if zero:
        print(f"  ({len(zero)} sender(s) matched nothing)")
    verb = {"delete": "PERMANENTLY DELETE", "trash": "move to Trash",
            "archive": f"move to '{args.to}'"}[args.action]
    print(f"\n==> {len(all_uids):,} messages would {verb}.")

    if not args.apply:
        print("\nDRY RUN — nothing changed. Re-run with --apply to execute.")
        try:
            M.logout()
        except Exception:
            pass
        return

    if args.action == "delete" and args.confirm != "DELETE":
        sys.exit("\nrefusing to permanently delete without "
                 "--confirm DELETE (irreversible).")

    # --- execute in batches ---
    # Capture the count BEFORE flagging so the post-expunge target is correct
    # even on servers (Gmail) that auto-expunge \Deleted during the loop.
    pre = mailbox_count(M, args.mailbox)
    done = 0
    failed: list[bytes] = []  # copy failed -> left in source, NEVER deleted
    dest = (args.to if args.action == "archive"
            else args.trash_folder if args.action == "trash" else None)
    # Smaller batches for the copy path: a failed 1000-COPY used to take the
    # whole batch down with it. 500 limits blast radius; salvage handles the rest.
    bsize = 1000 if args.action == "delete" else 500
    for batch in chunked(all_uids, bsize):
        ids = b",".join(batch).decode()
        if args.action == "delete":
            M.uid("STORE", ids, "+FLAGS", r"(\Deleted)")
            if have_uidplus:
                M.uid("EXPUNGE", ids)
            done += len(batch)
        elif have_move:
            M.uid("MOVE", ids, f'"{dest}"')
            done += len(batch)
        else:
            # COPY must be CONFIRMED before we delete the originals. If a batch
            # copy fails, salvage one message at a time so one bad/oversized
            # message can't doom the whole batch — and anything that still
            # won't copy is left in place, never deleted.
            if copy_verified(M, ids, dest):
                M.uid("STORE", ids, "+FLAGS", r"(\Deleted)")
                done += len(batch)
            else:
                for u in batch:
                    uid = u.decode()
                    if copy_verified(M, uid, dest):
                        M.uid("STORE", uid, "+FLAGS", r"(\Deleted)")
                        done += 1
                    else:
                        failed.append(u)
        sys.stdout.write(f"\r  {args.action}: {done:,}/{len(all_uids):,}")
        sys.stdout.flush()
    print()
    if failed:
        print(f"  ! {len(failed):,} message(s) could NOT be copied to "
              f"'{dest}' — left in {args.mailbox}, NOT deleted (no data lost).")
    # Drain the \Deleted flags. UID MOVE removes immediately (nothing to do);
    # the COPY/STORE fallback and non-UIDPLUS delete need a real expunge that
    # we poll to completion (iCloud drains lazily — see helper).
    needs_drain = not have_move or args.action == "delete"
    if needs_drain:
        target = max(0, pre - done)
        print(f"flagged {done:,}; expunging from {args.mailbox} "
              f"(may drain slowly on iCloud)...")
        final = expunge_until_drained(M, args.mailbox, target, args.action)
        print(f"Done. {done:,} {verb}; {args.mailbox} now {final:,} "
              f"(expected ~{target:,}).")
    else:
        print(f"Done. {done:,} messages processed ({verb}).")
    try:
        M.logout()
    except Exception:
        pass


# --- Unsubscribe -----------------------------------------------------------

def classify_unsub(list_unsub: str, list_unsub_post: str) -> tuple[str, str]:
    """Pick the best unsubscribe method from the List-Unsubscribe header(s).

    Preference order, most-to-least reliable to automate:
      1. one-click  — RFC 8058: an https URL *plus* a List-Unsubscribe-Post:
         'List-Unsubscribe=One-Click' header. A single POST unsubscribes with
         no confirmation page. This is what the Gmail/Apple "Unsubscribe"
         button uses.
      2. mailto     — send a message to the given address (we do it over SMTP).
      3. http       — an https link with NO one-click marker: almost always a
         landing page that needs a human click, so we only *report* it.
      4. none       — no usable header.

    Returns (method, target) where target is the URL or mailto: URI.
    """
    https = re.findall(r"<\s*(https?://[^>]+?)\s*>", list_unsub or "")
    mailtos = re.findall(r"<\s*(mailto:[^>]+?)\s*>", list_unsub or "")
    one_click = "one-click" in (list_unsub_post or "").lower()
    if https and one_click:
        return ("one-click", https[0])
    if mailtos:
        return ("mailto", mailtos[0])
    if https:
        return ("http", https[0])
    return ("none", "")


def fetch_unsub_method(M: imaplib.IMAP4_SSL, uid: bytes) -> tuple[str, str]:
    """Read the List-Unsubscribe headers of one message and classify them."""
    u = uid.decode() if isinstance(uid, bytes) else uid
    typ, data = M.uid(
        "fetch", u,
        "(BODY.PEEK[HEADER.FIELDS (LIST-UNSUBSCRIBE LIST-UNSUBSCRIBE-POST)])")
    if typ != "OK":
        return ("none", "")
    raw = b"".join(p[1] for p in data if isinstance(p, tuple))
    hdrs = parse_header_blob(raw)
    return classify_unsub(hdrs.get("list-unsubscribe", ""),
                          hdrs.get("list-unsubscribe-post", ""))


def do_one_click(url: str) -> tuple[bool, str]:
    """Fire an RFC 8058 one-click unsubscribe POST. Returns (ok, detail)."""
    body = b"List-Unsubscribe=One-Click"
    req = urllib.request.Request(
        url, data=body, method="POST",
        headers={"Content-Type": "application/x-www-form-urlencoded",
                 "User-Agent": UNSUB_UA})
    try:
        with urllib.request.urlopen(req, timeout=25) as r:
            return (r.status < 400, f"HTTP {r.status}")
    except urllib.error.HTTPError as e:
        return (e.code < 400, f"HTTP {e.code}")
    except Exception as e:  # noqa: BLE001 - network errors are varied
        return (False, f"{type(e).__name__}: {str(e)[:60]}")


def parse_mailto(uri: str) -> tuple[str, str, str]:
    """mailto:addr?subject=..&body=.. -> (to, subject, body)."""
    p = urllib.parse.urlparse(uri)
    q = urllib.parse.parse_qs(p.query)
    to = p.path
    subject = q.get("subject", ["unsubscribe"])[0]
    body = q.get("body", ["unsubscribe"])[0]
    return (to, subject, body)


def senders_from_csv(path: str, min_count: int) -> list[str]:
    """Pull newsletter senders out of a prior `analyze` senders.csv.

    Keeps rows flagged is_newsletter (they had a List-Unsubscribe header) with
    a message count >= min_count, so the candidate list is the bulk mail worth
    unsubscribing from — not every one-off sender."""
    out = []
    with Path(path).open(newline="") as f:
        for row in csv.DictReader(f):
            if row.get("is_newsletter", "").strip().lower() not in ("yes", "true", "1"):
                continue
            try:
                cnt = int(row.get("count", "0") or 0)
            except ValueError:
                cnt = 0
            if cnt >= min_count and row.get("address"):
                out.append(row["address"].strip().lower())
    return out


def cmd_unsubscribe(args: argparse.Namespace) -> None:
    preset = PRESETS.get(args.account, {})
    host = args.host or preset.get("host")
    port = args.port or preset.get("port", 993)
    if not host:
        sys.exit("error: --host required (or use --account icloud|gmail)")

    methods = {m.strip() for m in args.methods.split(",") if m.strip()}
    bad = methods - {"one-click", "mailto"}
    if bad:
        sys.exit(f"error: --methods supports one-click,mailto (got {bad})")

    # Candidate senders: explicit allowlist or harvested from an analyze CSV.
    if args.senders:
        senders = load_senders(args.senders)
    elif args.from_csv:
        senders = senders_from_csv(args.from_csv, args.min_count)
    else:
        sys.exit("error: pass --senders <file> or --from-csv <senders.csv>")
    if not senders:
        sys.exit("error: no candidate senders to process")

    password = get_password(args.user, args.keychain_service)
    M = connect(host, port, args.user, password)
    print(f"connected to {host} as {args.user}")

    mailbox = args.mailbox or ("[Gmail]/All Mail"
                               if args.account == "gmail" else "INBOX")
    M.select(f'"{mailbox}"', readonly=True)
    print(f"deriving unsubscribe links live from newest message per sender "
          f"in {mailbox} ({len(senders)} candidate senders)\n")

    # --- derive method per sender from its freshest message ---
    records = []  # (sender, count_in_mailbox, method, target)
    for s in senders:
        uids = search_sender(M, s, None)
        if not uids:
            records.append((s, 0, "absent", ""))
            continue
        method, target = fetch_unsub_method(M, uids[-1])  # newest
        records.append((s, len(uids), method, target))

    try:
        M.logout()
    except Exception:
        pass

    by_method = defaultdict(list)
    for r in records:
        by_method[r[2]].append(r)

    def show(method, note):
        rows = sorted(by_method.get(method, []), key=lambda x: -x[1])
        if not rows:
            return
        print(f"{method} ({len(rows)}) — {note}")
        for s, c, m, t in rows:
            print(f"  {c:>6,}  {s}")

    show("one-click", "RFC 8058 POST — will auto-unsubscribe")
    show("mailto", "send unsubscribe email over SMTP")
    show("http", "needs a browser visit — MANUAL, not fired")
    show("none", "no List-Unsubscribe header — MANUAL")
    show("absent", "no matching mail in this mailbox — skipped")

    actionable = [r for r in records if r[2] in methods]
    print(f"\n==> {len(actionable)} sender(s) would be unsubscribed "
          f"via {sorted(methods)}.")

    if not args.apply:
        print("\nDRY RUN — nothing sent. Re-run with --apply to execute.")
        return

    # --- execute ---
    stamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    out_dir = (Path(args.out) if args.out else DEFAULT_OUT) / \
        f"{args.account}_unsub_{stamp}"
    out_dir.mkdir(parents=True, exist_ok=True)
    log = []

    # one-click POSTs
    oc = [r for r in actionable if r[2] == "one-click"]
    if oc:
        print(f"\nfiring {len(oc)} one-click POST(s)...")
        for s, c, m, url in oc:
            ok, detail = do_one_click(url)
            print(f"  {'ok ' if ok else 'ERR'} {detail:12}  {s}")
            log.append((s, c, "one-click", "ok" if ok else "fail", detail))
            time.sleep(0.5)

    # mailto unsubscribes over SMTP
    mt = [r for r in actionable if r[2] == "mailto"]
    if mt:
        sp = SMTP_PRESETS.get(args.account, {})
        smtp_host = args.smtp_host or sp.get("host")
        smtp_port = args.smtp_port or sp.get("port", 587)
        if not smtp_host:
            print("  ! no SMTP host (use --smtp-host); skipping mailto unsubs")
        else:
            print(f"\nsending {len(mt)} mailto unsubscribe(s) via "
                  f"{smtp_host}...")
            S = smtplib.SMTP(smtp_host, smtp_port, timeout=30)
            try:
                S.starttls()
                S.login(args.user, password)
                for s, c, m, uri in mt:
                    to, subj, body = parse_mailto(uri)
                    em = EmailMessage()
                    em["From"] = args.user
                    em["To"] = to
                    em["Subject"] = subj
                    em.set_content(body)
                    try:
                        S.send_message(em)
                        print(f"  sent  {s}  -> {to[:45]}")
                        log.append((s, c, "mailto", "sent", to))
                    except Exception as e:  # noqa: BLE001
                        print(f"  FAIL  {s}: {str(e)[:50]}")
                        log.append((s, c, "mailto", "fail", str(e)[:80]))
                    time.sleep(0.3)
            finally:
                try:
                    S.quit()
                except Exception:
                    pass

    # write the log
    with (out_dir / "unsubscribe_log.csv").open("w", newline="") as f:
        w = csv.writer(f)
        w.writerow(["sender", "count_in_mailbox", "method", "result", "detail"])
        w.writerows(log)
    ok_n = sum(1 for r in log if r[3] in ("ok", "sent"))
    print(f"\nDone. {ok_n}/{len(log)} succeeded. Log: "
          f"{out_dir / 'unsubscribe_log.csv'}")
    print("Note: senders may take up to 10 business days to stop (CAN-SPAM).")


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(description="bulk IMAP mailbox cleanup")
    sub = p.add_subparsers(dest="cmd", required=True)

    a = sub.add_parser("analyze", help="READ-ONLY: measure the mailbox")
    a.add_argument("--account", default="icloud",
                   help="preset: icloud | gmail | custom label")
    a.add_argument("--user", required=True, help="full email address / login")
    a.add_argument("--host", help="IMAP host (overrides preset)")
    a.add_argument("--port", type=int, help="IMAP port (default 993)")
    a.add_argument("--keychain-service",
                   help="macOS Keychain service name holding the password")
    a.add_argument("--mailbox", action="append",
                   help="mailbox to scan (repeatable; default INBOX)")
    a.add_argument("--all-mailboxes", action="store_true",
                   help="scan every mailbox except Trash/Junk")
    a.add_argument("--out", help=f"output dir (default {DEFAULT_OUT})")
    a.set_defaults(func=cmd_analyze)

    # act: delete / trash / archive by approved sender list -------------
    c = sub.add_parser("act", help="delete/trash/archive by sender allowlist")
    c.add_argument("--account", default="icloud")
    c.add_argument("--user", required=True)
    c.add_argument("--host")
    c.add_argument("--port", type=int)
    c.add_argument("--keychain-service")
    c.add_argument("--senders", required=True,
                   help="text file: one sender address per line (# = comment)")
    c.add_argument("--action", required=True,
                   choices=["delete", "trash", "archive"])
    c.add_argument("--mailbox", default=None,
                   help="mailbox to act within "
                        "(default INBOX; Gmail: [Gmail]/All Mail)")
    c.add_argument("--to", default="Financial",
                   help="destination folder for --action archive")
    c.add_argument("--trash-folder", default=None,
                   help="Trash folder name for --action trash "
                        "(default 'Deleted Items'; Gmail: [Gmail]/Trash)")
    c.add_argument("--older-than",
                   help="only messages BEFORE this date (YYYY-MM-DD)")
    c.add_argument("--apply", action="store_true",
                   help="actually execute (default is dry-run)")
    c.add_argument("--confirm",
                   help="must equal DELETE to run --action delete --apply")
    c.add_argument("--no-verify", action="store_true",
                   help="skip client-side exact From: verification (faster, "
                        "but trusts the server's loose SEARCH FROM matching)")
    c.set_defaults(func=cmd_act)

    # unsubscribe: stop bulk senders at the source -----------------------
    u = sub.add_parser(
        "unsubscribe",
        help="unsubscribe from bulk senders via List-Unsubscribe "
             "(one-click POST + mailto)")
    u.add_argument("--account", default="icloud")
    u.add_argument("--user", required=True)
    u.add_argument("--host")
    u.add_argument("--port", type=int)
    u.add_argument("--keychain-service")
    u.add_argument("--senders",
                   help="text file: one sender address per line (# = comment)")
    u.add_argument("--from-csv", dest="from_csv",
                   help="harvest newsletter senders from a prior analyze "
                        "senders.csv instead of a hand-written list")
    u.add_argument("--min-count", dest="min_count", type=int, default=3,
                   help="with --from-csv: only senders with >= this many "
                        "messages (default 3)")
    u.add_argument("--mailbox", default=None,
                   help="mailbox to read unsubscribe links from "
                        "(default INBOX; Gmail: [Gmail]/All Mail)")
    u.add_argument("--methods", default="one-click",
                   help="comma list of methods to fire: one-click,mailto "
                        "(default one-click only). mailto is OPT-IN: it sends "
                        "email from your account and many unsubscribe mailboxes "
                        "are dead, so it's low-yield and generates NDR bounce-"
                        "backs. Pass --methods one-click,mailto to include it. "
                        "(http/none are always report-only.)")
    u.add_argument("--smtp-host", dest="smtp_host",
                   help="SMTP host for mailto unsubs (overrides preset)")
    u.add_argument("--smtp-port", dest="smtp_port", type=int,
                   help="SMTP port (default 587 STARTTLS)")
    u.add_argument("--apply", action="store_true",
                   help="actually unsubscribe (default is dry-run)")
    u.add_argument("--out", help=f"log output dir (default {DEFAULT_OUT})")
    u.set_defaults(func=cmd_unsubscribe)
    return p


def main() -> None:
    args = build_parser().parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
