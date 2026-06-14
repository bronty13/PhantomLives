#!/usr/bin/env python3
# =============================================================================
#   APPLE BOOKS ARCHIVER
#   File:     books_archiver.py
#   Version:  1.0.0
#   Requires: Python 3.9+ (standard library only)
#
#   Permanent, append-only archive of Apple Books highlights + notes from the
#   iBooksX containers: annotations in AEAnnotation/AEAnnotation*.sqlite
#   (ZAEANNOTATION) joined to book titles in BKLibrary/BKLibrary*.sqlite
#   (ZBKLIBRARYASSET). Highlights/notes are mutable, so the manifest versions by
#   (id, content-hash). Outputs per-book Markdown + a collapsible HTML + CSV index.
#
#   Usage:  books_archiver.py --db <iBooksX Documents dir> --archive <dir>
# =============================================================================
import argparse
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from applearchive_common import (  # noqa: E402
    open_ro, rows, has_table, s, cd_date, san, short_hash, content_hash,
    load_manifest, manifest_keys, append_manifest, latest_per_id, write_csv,
    html_page, esc,
)

__version__ = '1.0.0'

STYLE = {0: 'Underline', 1: 'Green', 2: 'Blue', 3: 'Yellow', 4: 'Pink', 5: 'Purple'}


def _find(dirpath, sub, prefix):
    d = Path(dirpath)
    cands = list((d / sub).glob(f'{prefix}*.sqlite')) if (d / sub).exists() else []
    if not cands:
        cands = list(d.glob(f'**/{prefix}*.sqlite'))
    return cands[0] if cands else None


def read_books(docs_dir):
    assets = {}
    bk = _find(docs_dir, 'BKLibrary', 'BKLibrary')
    if bk:
        conn = open_ro(bk)
        if has_table(conn, 'ZBKLIBRARYASSET'):
            cols = {r[1] for r in rows(conn, 'PRAGMA table_info(ZBKLIBRARYASSET)')}
            au = 'ZAUTHOR' if 'ZAUTHOR' in cols else ('ZAUTHORNAMES' if 'ZAUTHORNAMES' in cols else 'NULL')
            for aid, title, author in rows(conn,
                    f'SELECT ZASSETID, ZTITLE, {au} FROM ZBKLIBRARYASSET'):
                assets[s(aid)] = {'title': s(title) or 'Unknown book', 'author': s(author)}
        conn.close()

    out = []
    an = _find(docs_dir, 'AEAnnotation', 'AEAnnotation')
    if an:
        conn = open_ro(an)
        if has_table(conn, 'ZAEANNOTATION'):
            for aid, sel, note, loc, created, style in rows(conn,
                    'SELECT ZANNOTATIONASSETID, ZANNOTATIONSELECTEDTEXT, ZANNOTATIONNOTE, '
                    '       ZANNOTATIONLOCATION, ZANNOTATIONCREATIONDATE, ZANNOTATIONSTYLE '
                    'FROM ZAEANNOTATION '
                    'WHERE (ZANNOTATIONDELETED IS NULL OR ZANNOTATIONDELETED = 0) '
                    '  AND (ZANNOTATIONSELECTEDTEXT IS NOT NULL OR ZANNOTATIONNOTE IS NOT NULL)'):
                book = assets.get(s(aid), {'title': 'Unknown book', 'author': ''})
                out.append({
                    'id': short_hash(s(aid), s(loc), (s(sel) or s(note))[:40]),
                    'book': book['title'], 'author': book['author'],
                    'highlight': s(sel), 'note': s(note),
                    'color': STYLE.get(int(style or 0), ''),
                    'location': s(loc), 'created': cd_date(created),
                })
        conn.close()
    return out


def build_views(archive, entries):
    archive = Path(archive)
    books_root = archive / 'books'; books_root.mkdir(parents=True, exist_ok=True)
    current = latest_per_id(entries)
    by_book = {}
    for e in current:
        by_book.setdefault(e['book'], []).append(e)

    index_rows, sections = [], []
    for book in sorted(by_book):
        items = sorted(by_book[book], key=lambda e: (e.get('location') or '', e.get('created') or ''))
        author = next((e['author'] for e in items if e['author']), '')
        md = [f'# {book}'] + ([f'_{author}_'] if author else []) + [f'_{len(items)} highlights_', '']
        cards = []
        for e in items:
            if e['highlight']:
                md.append(f'> {e["highlight"]}')
            if e['note']:
                md.append(f'  — {e["note"]}')
            md.append('')
            hl = f'<div class="hl">{esc(e["highlight"])}</div>' if e['highlight'] else ''
            nt = f'<div class="sub">📝 {esc(e["note"])}</div>' if e['note'] else ''
            tag = f'<span class="tag">{esc(e["color"])}</span>' if e['color'] else ''
            cards.append(f'<details class="item"><summary>{tag}{esc((e["highlight"] or e["note"])[:90])}</summary>{hl}{nt}'
                         f'<div class="sub">{esc(e["created"])}</div></details>')
        (books_root / f'{san(book)}.md').write_text('\n'.join(md) + '\n', encoding='utf-8')
        sections.append(f'<details class="list" open><summary class="lh">{esc(book)}'
                        + (f' <span class="cnt">— {esc(author)}</span>' if author else '')
                        + f' <span class="cnt">({len(items)})</span></summary>' + ''.join(cards) + '</details>')
        index_rows.append({'book': book, 'author': author, 'highlights': len(items)})

    doc = """<!DOCTYPE html><html><head><meta charset="utf-8"><title>Books ({n})</title><style>
body{{font:15px -apple-system,Helvetica,Arial,sans-serif;background:#f2f2f7;margin:0;padding:24px}}
h1{{font-size:20px}} input{{font-size:15px;padding:8px 12px;width:300px;border:1px solid #ccc;border-radius:8px;margin-bottom:16px}}
details.list{{margin:14px 0;max-width:760px}} details.list>summary{{font-size:17px;font-weight:600;cursor:pointer}}
.cnt{{color:#999;font-size:13px;font-weight:400}}
details.item{{background:#fff;border-radius:10px;margin:6px 0;padding:8px 12px}}
details.item>summary{{cursor:pointer}} .hl{{margin:6px 0;border-left:3px solid #ffcc00;padding-left:8px;white-space:pre-wrap}}
.sub{{color:#888;font-size:12px}} .tag{{font-size:11px;color:#999;margin-right:6px}}
</style></head><body><h1>Books ({n} highlights)</h1>
<input id="q" placeholder="Filter…" oninput="f()"><div id="list">{body}</div>
<script>function f(){{var q=document.getElementById('q').value.toLowerCase();
document.querySelectorAll('details.item').forEach(function(e){{e.style.display=e.textContent.toLowerCase().indexOf(q)<0?'none':''}});}}</script>
</body></html>""".format(n=len(current), body='\n'.join(sections))
    (archive / 'books.html').write_text(doc, encoding='utf-8')
    write_csv(archive / '_index.csv', ['book', 'author', 'highlights'], index_rows)
    return len(current), len(by_book)


def run_archive(db, archive):
    archive = Path(archive); archive.mkdir(parents=True, exist_ok=True)
    mpath = archive / 'manifest.jsonl'
    seen = manifest_keys(load_manifest(mpath))
    new = []
    for e in read_books(db):
        key = (e['id'], content_hash(e['highlight'], e['note']))
        if key in seen:
            continue
        seen.add(key); rec = dict(e); rec['hash'] = key[1]; new.append(rec)
    append_manifest(mpath, new)
    hl, books = build_views(archive, load_manifest(mpath))
    return {'new': len(new), 'highlights': hl, 'books': books}


def main():
    ap = argparse.ArgumentParser(prog='books_archiver',
        description='Append-only Apple Books highlights/notes archiver.')
    ap.add_argument('--db', required=True, help='iBooksX Documents dir (AEAnnotation/ + BKLibrary/)')
    ap.add_argument('--archive', required=True, help='archive root directory')
    ap.add_argument('--version', action='version', version=f'%(prog)s {__version__}')
    a = ap.parse_args()
    if not Path(a.db).exists():
        ap.error(f'Books data dir not found: {a.db}')
    r = run_archive(a.db, a.archive)
    print(f'Books: +{r["new"]} new; {r["highlights"]} highlights across {r["books"]} book(s).')


if __name__ == '__main__':
    main()
