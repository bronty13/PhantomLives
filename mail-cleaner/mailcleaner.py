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

__version__ = "0.1.0"

import argparse
import csv
import imaplib
import json
import os
import re
import subprocess
import sys
from collections import Counter, defaultdict
from datetime import datetime, timezone
from email.header import decode_header, make_header
from email.utils import parseaddr, parsedate_to_datetime
from pathlib import Path

# --- Account presets -------------------------------------------------------

PRESETS = {
    "icloud": {"host": "imap.mail.me.com", "port": 993},
    "gmail": {"host": "imap.gmail.com", "port": 993},
}

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
        mailboxes = args.mailbox or ["INBOX"]

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


def cmd_act(args: argparse.Namespace) -> None:
    preset = PRESETS.get(args.account, {})
    host = args.host or preset.get("host")
    port = args.port or preset.get("port", 993)
    if not host:
        sys.exit("error: --host required (or use --account icloud|gmail)")

    senders = load_senders(args.senders)
    if not senders:
        sys.exit(f"error: no senders in {args.senders}")

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
    done = 0
    for batch in chunked(all_uids, 1000):
        ids = b",".join(batch).decode()
        if args.action == "archive":
            if have_move:
                M.uid("MOVE", ids, f'"{args.to}"')
            else:
                M.uid("COPY", ids, f'"{args.to}"')
                M.uid("STORE", ids, "+FLAGS", r"(\Deleted)")
        elif args.action == "trash":
            trash = args.trash_folder
            if have_move:
                M.uid("MOVE", ids, f'"{trash}"')
            else:
                M.uid("COPY", ids, f'"{trash}"')
                M.uid("STORE", ids, "+FLAGS", r"(\Deleted)")
        elif args.action == "delete":
            M.uid("STORE", ids, "+FLAGS", r"(\Deleted)")
            if have_uidplus:
                M.uid("EXPUNGE", ids)
        done += len(batch)
        sys.stdout.write(f"\r  {args.action}: {done:,}/{len(all_uids):,}")
        sys.stdout.flush()
    # final expunge to clear any \Deleted flags (copy-fallback or non-UIDPLUS)
    if args.action in ("delete", "trash", "archive"):
        try:
            M.expunge()
        except Exception:
            pass
    print(f"\nDone. {done:,} messages processed ({verb}).")
    try:
        M.logout()
    except Exception:
        pass


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
    c.add_argument("--mailbox", default="INBOX",
                   help="mailbox to act within (default INBOX)")
    c.add_argument("--to", default="Financial",
                   help="destination folder for --action archive")
    c.add_argument("--trash-folder", default="Deleted Items",
                   help="Trash folder name for --action trash")
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
    return p


def main() -> None:
    args = build_parser().parse_args()
    args.func(args)


if __name__ == "__main__":
    main()
