#!/usr/bin/env python3
# =============================================================================
#   ARCHIVE INDEX  (landing page)
#   File:     archive_index.py
#   Version:  1.0.0
#   Requires: Python 3.9+ (standard library only)
#
#   Builds ONE landing page linking every archive a source has under ~/Downloads
#   (photos, messages, notes, reminders, safari, voice memos, calls, calendar,
#   books, podcasts, stickies). Each card links the archive's entry HTML pages and
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

# Each kind: archive-folder suffix, label, the entry HTML pages (in preference
# order), and how to count items (an _index.csv, a manifest.jsonl, or a glob).
KINDS = [
    ('PhotoArchive',      'Photos',      [],                                              ('glob', 'originals/**/*')),
    ('MessagesArchive',   'Messages',    ['contacts.html'],                               ('manifest', 'manifest.jsonl')),
    ('NotesArchive',      'Notes',       ['notes.html'],                                  ('csv', '_index.csv')),
    ('RemindersArchive',  'Reminders',   ['reminders.html'],                              ('csv', '_index.csv')),
    ('SafariArchive',     'Safari',      ['history.html', 'bookmarks.html', 'readinglist.html'], ('csv', 'history.csv')),
    ('VoiceMemosArchive', 'Voice Memos', ['voicememos.html'],                             ('glob', 'recordings/*.m4a')),
    ('CallsArchive',      'Call history',['calls.html'],                                  ('csv', 'calls.csv')),
    ('CalendarArchive',   'Calendar',    ['calendar.html'],                               ('manifest', 'manifest.jsonl')),
    ('BooksArchive',      'Books',       ['books.html'],                                  ('csv', '_index.csv')),
    ('PodcastsArchive',   'Podcasts',    ['podcasts.html'],                               ('csv', '_index.csv')),
    ('StickiesArchive',   'Stickies',    ['stickies.html'],                               ('csv', '_index.csv')),
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


def build(name, downloads, out):
    downloads = Path(downloads)
    cards = []
    for suffix, label, pages, cspec in KINDS:
        folder = downloads / f'{name}{suffix}'
        if not folder.is_dir():
            continue
        rel = f'{name}{suffix}'
        links = [f'<a href="{html.escape(rel)}/{html.escape(p)}">{html.escape(p.split(".")[0])}</a>'
                 for p in pages if (folder / p).exists()]
        links.append(f'<a href="{html.escape(rel)}/">browse files</a>')
        n = count(folder, cspec)
        stat = f'{n:,} items' if isinstance(n, int) else ''
        cards.append(
            f'<div class="card"><div class="lbl">{html.escape(label)}</div>'
            f'<div class="stat">{stat}</div><div class="links">{" · ".join(links)}</div></div>')

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
                    help='dir holding the <Name>*Archive folders')
    ap.add_argument('--out', default=None, help='output html (default <downloads>/<Name>-Archives.html)')
    ap.add_argument('--version', action='version', version='%(prog)s 1.0.0')
    a = ap.parse_args()
    out = a.out or str(Path(a.downloads) / f'{a.name}-Archives.html')
    n = build(a.name, a.downloads, out)
    print(f'Archive index: {n} archive(s) linked → {out}')


if __name__ == '__main__':
    main()
