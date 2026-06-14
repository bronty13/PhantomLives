#!/usr/bin/env python3
"""Shared helpers for the Apple data archivers (notes_archiver, reminders_archiver).

Common model: a PERMANENT, APPEND-ONLY archive built incrementally.
  • manifest.jsonl is the source of truth — one JSON line per *version* of an item
    (keyed by id + content-hash). Notes/reminders are MUTABLE, so a new line is
    appended whenever an item's content changes — old versions are kept forever,
    and items deleted on the source device remain. Nothing is ever lost.
  • Human-facing views (text/HTML/CSV) are DERIVED — regenerated from the manifest
    each run (latest version per id), so the layout can improve safely.
Standard library only.
"""
import csv
import hashlib
import html
import json
import re
import sqlite3
from datetime import datetime
from pathlib import Path

CORE_DATA_EPOCH = 978307200   # 2001-01-01 → unix seconds


def open_ro(db):
    """Open a SQLite file read-only + immutable (works on WAL snapshots)."""
    return sqlite3.connect(f'file:{db}?mode=ro&immutable=1', uri=True)


def rows(conn, sql, params=()):
    try:
        return conn.execute(sql, params).fetchall()
    except sqlite3.DatabaseError:
        return []


def has_table(conn, name):
    return bool(rows(conn, "SELECT 1 FROM sqlite_master WHERE type='table' AND name=?", (name,)))


def s(x):
    """Coerce any DB value to a trimmed string."""
    return ('' if x is None else str(x)).strip()


def cd_dt(val):
    """Core Data timestamp (seconds since 2001) → naive local datetime, or None."""
    if val is None:
        return None
    try:
        return datetime.fromtimestamp(float(val) + CORE_DATA_EPOCH)
    except (ValueError, OverflowError, OSError):
        return None


def cd_date(val, fmt='%Y-%m-%d %H:%M'):
    """Core Data timestamp (seconds since 2001) → formatted local datetime, or ''."""
    dt = cd_dt(val)
    return dt.strftime(fmt) if dt else ''


def san(name):
    """Filesystem-safe name."""
    out = re.sub(r'[<>:"/\\|?*\x00-\x1f]', '_', name or '')
    return out.strip().strip('.') or 'untitled'


def slug(text, mx=60):
    base = san(text)[:mx].strip().strip('._') or 'untitled'
    return base


def short_hash(*parts):
    return hashlib.sha1('|'.join(str(p) for p in parts).encode('utf-8')).hexdigest()[:8]


def content_hash(*parts):
    return hashlib.sha1(''.join(str(p) for p in parts).encode('utf-8')).hexdigest()


# ─── Append-only manifest ────────────────────────────────────────────────────

def load_manifest(path):
    out = []
    p = Path(path)
    if not p.exists():
        return out
    with p.open(encoding='utf-8') as fh:
        for line in fh:
            line = line.strip()
            if line:
                try:
                    out.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
    return out


def manifest_keys(entries):
    """The (id, hash) dedup keys already recorded."""
    return {(e.get('id'), e.get('hash')) for e in entries}


def append_manifest(path, new_entries):
    if not new_entries:
        return
    with Path(path).open('a', encoding='utf-8') as fh:
        for e in new_entries:
            fh.write(json.dumps(e, ensure_ascii=False) + '\n')


def latest_per_id(entries):
    """Latest version per id, preserving first-seen order of ids."""
    order, latest = [], {}
    for e in entries:
        i = e.get('id')
        if i not in latest:
            order.append(i)
        latest[i] = e            # later lines (appended later) win
    return [latest[i] for i in order]


def write_csv(path, fieldnames, dict_rows):
    with Path(path).open('w', newline='', encoding='utf-8') as fh:
        w = csv.DictWriter(fh, fieldnames=fieldnames)
        w.writeheader()
        w.writerows(dict_rows)


# ─── HTML ────────────────────────────────────────────────────────────────────

def html_page(title, body_html, search=True):
    head = f"""<!DOCTYPE html><html><head><meta charset="utf-8"><title>{html.escape(title)}</title>
<style>
body{{font:15px -apple-system,Helvetica,Arial,sans-serif;background:#f2f2f7;margin:0;padding:24px;color:#000}}
h1{{font-size:20px}} input{{font-size:15px;padding:8px 12px;width:300px;border:1px solid #ccc;border-radius:8px;margin-bottom:16px}}
.item{{background:#fff;border-radius:12px;padding:12px 16px;margin:8px 0;max-width:760px}}
.t{{font-weight:600;font-size:16px}} .meta{{color:#888;font-size:12px;margin:2px 0 6px}}
.body{{white-space:pre-wrap;word-wrap:break-word}} .done{{color:#999;text-decoration:line-through}}
a{{color:#1982fc;text-decoration:none}} .tag{{color:#999;font-size:11px;text-transform:uppercase;margin-right:6px}}
</style></head><body><h1>{html.escape(title)}</h1>
"""
    box = ('<input id="q" placeholder="Filter…" oninput="f()">'
           '<div id="list">') if search else '<div id="list">'
    tail = """</div><script>
function f(){var q=document.getElementById('q').value.toLowerCase();
document.querySelectorAll('.item').forEach(function(e){
e.style.display=e.textContent.toLowerCase().indexOf(q)<0?'none':''});}
</script></body></html>"""
    return head + box + body_html + tail


def esc(x):
    return html.escape(s(x))
