#!/usr/bin/env python3
# =============================================================================
#   ARCHIVE INDEX  (landing page)
#   File:     archive_index.py
#   Version:  1.1.0
#   Requires: Python 3.9+ (standard library only)
#
#   Builds ONE landing page linking every archive a source has. All of a source's
#   archives live consolidated under ONE folder: ~/Downloads/<Name> Archive/, with a
#   clean per-kind subfolder each (Photos, Messages, Mail, …). The landing page is
#   written to that folder's root. Each card links the archive's entry HTML pages and
#   a "browse files" link, with a quick item count. Read-only; regenerable.
#
#   Usage:  archive_index.py --name <SourceName> [--downloads <dir>] [--out <file>]
# =============================================================================
import argparse
import csv
import html
import os
import sys
from pathlib import Path

# Each kind: per-kind subfolder name (under "<Name> Archive/"), label, the entry
# HTML pages (in preference order), and how to count items (_index.csv / manifest /
# glob).
KINDS = [
    ('Photos',      'Photos',      [],                                              ('glob', 'originals/**/*')),
    ('Messages',    'Messages',    ['contacts.html'],                               ('manifest', 'manifest.jsonl')),
    ('Notes',       'Notes',       ['notes.html'],                                  ('csv', '_index.csv')),
    ('Reminders',   'Reminders',   ['reminders.html'],                              ('csv', '_index.csv')),
    ('Safari',      'Safari',      ['history.html', 'bookmarks.html', 'readinglist.html'], ('csv', 'history.csv')),
    ('Voice Memos', 'Voice Memos', ['voicememos.html'],                             ('glob', 'recordings/*.m4a')),
    ('Calls',       'Call history',['calls.html'],                                  ('csv', 'calls.csv')),
    ('Calendar',    'Calendar',    ['calendar.html'],                               ('manifest', 'manifest.jsonl')),
    ('Books',       'Books',       ['books.html'],                                  ('csv', '_index.csv')),
    ('Podcasts',    'Podcasts',    ['podcasts.html'],                               ('csv', '_index.csv')),
    ('Stickies',    'Stickies',    ['stickies.html'],                               ('csv', '_index.csv')),
    ('Mail',        'Mail',        ['mail.html'],                                   ('manifest', 'manifest.jsonl')),
]


def count(folder, spec):
    kind, arg = spec
    try:
        if kind == 'csv':
            p = folder / arg
            return max(0, sum(1 for _ in p.open(encoding='utf-8')) - 1) if p.exists() else None
        if kind == 'manifest':
            p = folder / arg
            return sum(1 for line in p.open(encoding='utf-8') if line.strip()) if p.exists() else None
        if kind == 'glob':
            return sum(1 for _ in folder.glob(arg))
    except OSError:
        return None
    return None


def base_dir(downloads, name):
    """The consolidated archive folder for a source: ~/Downloads/<Name> Archive/."""
    return Path(downloads) / f'{name} Archive'


def build(name, downloads, out):
    base = base_dir(downloads, name)
    cards = []
    for subdir, label, pages, cspec in KINDS:
        folder = base / subdir
        if not folder.is_dir():
            continue
        rel = subdir                                   # links are relative to base/
        links = [f'<a href="{html.escape(rel)}/{html.escape(p)}">{html.escape(p.split(".")[0])}</a>'
                 for p in pages if (folder / p).exists()]
        links.append(f'<a href="{html.escape(rel)}/">browse files</a>')
        n = count(folder, cspec)
        stat = f'{n:,} items' if isinstance(n, int) else ''
        cards.append(
            f'<div class="card"><div class="lbl">{html.escape(label)}</div>'
            f'<div class="stat">{stat}</div><div class="links">{" · ".join(links)}</div></div>')

    base.mkdir(parents=True, exist_ok=True)
    body = '\n'.join(cards) or '<p>No archives found yet.</p>'
    doc = f"""<!DOCTYPE html><html><head><meta charset="utf-8"><title>{html.escape(name)} — Archives</title>
<style>
body{{font:15px -apple-system,Helvetica,Arial,sans-serif;background:#f2f2f7;margin:0;padding:32px;color:#000}}
h1{{font-size:24px}} .sub{{color:#888;margin-bottom:20px}}
.grid{{display:grid;grid-template-columns:repeat(auto-fill,minmax(240px,1fr));gap:14px;max-width:1000px}}
.card{{background:#fff;border-radius:14px;padding:16px 18px}}
.lbl{{font-weight:600;font-size:17px}} .stat{{color:#999;font-size:13px;margin:2px 0 8px}}
.links a{{color:#1982fc;text-decoration:none;font-size:13px}}
</style></head><body>
<h1>{html.escape(name)} — Archives</h1>
<div class="sub">Permanent, preservation archives. Every card links the browsable views + the raw files.</div>
<div class="grid">{body}</div>
</body></html>"""
    Path(out).write_text(doc, encoding='utf-8')
    return len(cards)


def main():
    ap = argparse.ArgumentParser(prog='archive_index',
        description='Build a landing page linking all of a source\'s archives.')
    ap.add_argument('--name', required=True, help='source name (e.g. Rachel)')
    ap.add_argument('--downloads', default=str(Path.home() / 'Downloads'),
                    help='dir holding the "<Name> Archive/" consolidated folder')
    ap.add_argument('--out', default=None,
                    help='output html (default <downloads>/<Name> Archive/<Name>-Archives.html)')
    ap.add_argument('--version', action='version', version='%(prog)s 1.1.0')
    a = ap.parse_args()
    out = a.out or str(base_dir(a.downloads, a.name) / f'{a.name}-Archives.html')
    n = build(a.name, a.downloads, out)
    print(f'Archive index: {n} archive(s) linked → {out}')


if __name__ == '__main__':
    main()
