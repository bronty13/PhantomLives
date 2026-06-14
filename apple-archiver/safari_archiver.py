#!/usr/bin/env python3
# =============================================================================
#   APPLE SAFARI ARCHIVER
#   File:     safari_archiver.py
#   Version:  1.0.0
#   Requires: Python 3.9+ (standard library only)
#
#   Permanent, append-only archive of Safari history + bookmarks + reading list
#   from a pulled Safari data dir (History.db + Bookmarks.plist).
#     • History — immutable visit events (append-only, keyed by url+time).
#     • Bookmarks & Reading List — mutable, versioned by (url, content-hash).
#   Outputs history.html / bookmarks.html / readinglist.html + CSVs.
#
#   Usage:  safari_archiver.py --db <Safari dir> --archive <dir>
# =============================================================================
import argparse
import os
import plistlib
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from applearchive_common import (  # noqa: E402
    open_ro, rows, has_table, s, cd_date, short_hash, content_hash,
    load_manifest, manifest_keys, append_manifest, write_csv, html_page, esc,
)

__version__ = '1.0.0'
HTML_VISIT_CAP = 4000   # most-recent visits rendered to HTML (all kept in manifest + csv)


def read_history(db):
    conn = open_ro(db)
    if not has_table(conn, 'history_visits'):
        conn.close(); return []
    out = []
    for url, title, vtime in rows(conn,
            'SELECT i.url, v.title, v.visit_time '
            'FROM history_visits v JOIN history_items i ON i.id = v.history_item'):
        when = cd_date(vtime, '%Y-%m-%d %H:%M:%S')
        out.append({'kind': 'visit', 'url': s(url), 'title': s(title), 'date': when,
                    'id': short_hash(s(url), when)})
    conn.close()
    return out


def _walk_bookmarks(node, folder, bms, rl):
    t = node.get('WebBookmarkType')
    if t == 'WebBookmarkTypeList':
        name = s(node.get('Title'))
        path = f'{folder}/{name}' if folder and name else (name or folder)
        for ch in node.get('Children', []) or []:
            _walk_bookmarks(ch, path, bms, rl)
    elif t == 'WebBookmarkTypeLeaf':
        url = s(node.get('URLString'))
        title = s((node.get('URIDictionary') or {}).get('title')) or url
        if 'ReadingList' in node:
            added = node['ReadingList'].get('DateAdded')
            rl.append({'kind': 'readinglist', 'url': url, 'title': title,
                       'date': s(added)[:19], 'id': 'rl:' + url})
        else:
            bms.append({'kind': 'bookmark', 'url': url, 'title': title,
                        'folder': folder or 'Bookmarks', 'id': 'bm:' + url})


def read_bookmarks(plist_path):
    bms, rl = [], []
    try:
        with open(plist_path, 'rb') as fh:
            root = plistlib.load(fh)
        _walk_bookmarks(root, '', bms, rl)
    except (OSError, plistlib.InvalidFileException, ValueError):
        pass
    return bms, rl


def _list_html(title, items, link_meta):
    cards = []
    for e in items:
        cards.append(f'<div class="item"><div class="t"><a href="{esc(e["url"])}">{esc(e["title"])}</a></div>'
                     f'<div class="meta">{esc(link_meta(e))}</div></div>')
    return html_page(title, '\n'.join(cards))


def build_views(archive, entries):
    archive = Path(archive)
    visits = [e for e in entries if e.get('kind') == 'visit']
    bms = [e for e in entries if e.get('kind') == 'bookmark']
    rl = [e for e in entries if e.get('kind') == 'readinglist']

    # History (most-recent first; cap HTML, full CSV).
    visits.sort(key=lambda e: e.get('date') or '', reverse=True)
    seen_bm, latest_bm = set(), []      # latest version per bookmark url
    for e in bms:
        if e['url'] not in seen_bm:
            seen_bm.add(e['url']); latest_bm.append(e)
    seen_rl, latest_rl = set(), []
    for e in rl:
        if e['url'] not in seen_rl:
            seen_rl.add(e['url']); latest_rl.append(e)

    vcards = [f'<div class="item"><div class="t"><a href="{esc(e["url"])}">{esc(e["title"] or e["url"])}</a></div>'
              f'<div class="meta">{esc(e["date"])}</div></div>' for e in visits[:HTML_VISIT_CAP]]
    cap_note = (f'<div class="meta" style="margin:8px 0">Showing the most recent '
                f'{HTML_VISIT_CAP} of {len(visits)} visits (full set in history.csv).</div>'
                if len(visits) > HTML_VISIT_CAP else '')
    (archive / 'history.html').write_text(
        html_page(f'Safari history ({len(visits)})', cap_note + '\n'.join(vcards)), encoding='utf-8')
    write_csv(archive / 'history.csv', ['date', 'title', 'url'],
              [{'date': e['date'], 'title': e['title'], 'url': e['url']} for e in visits])

    (archive / 'bookmarks.html').write_text(
        _list_html(f'Safari bookmarks ({len(latest_bm)})', latest_bm, lambda e: e.get('folder', '')),
        encoding='utf-8')
    write_csv(archive / 'bookmarks.csv', ['folder', 'title', 'url'],
              [{'folder': e.get('folder', ''), 'title': e['title'], 'url': e['url']} for e in latest_bm])

    (archive / 'readinglist.html').write_text(
        _list_html(f'Safari reading list ({len(latest_rl)})', latest_rl, lambda e: e.get('date', '')),
        encoding='utf-8')

    write_csv(archive / '_index.csv', ['section', 'count'],
              [{'section': 'history visits', 'count': len(visits)},
               {'section': 'bookmarks', 'count': len(latest_bm)},
               {'section': 'reading list', 'count': len(latest_rl)}])
    return len(visits), len(latest_bm), len(latest_rl)


def run_archive(db, archive):
    archive = Path(archive); archive.mkdir(parents=True, exist_ok=True)
    d = Path(db)
    hist_db = d / 'History.db' if d.is_dir() else d
    bm_plist = (d / 'Bookmarks.plist') if d.is_dir() else d.parent / 'Bookmarks.plist'

    mpath = archive / 'manifest.jsonl'
    seen = manifest_keys(load_manifest(mpath))
    new = []

    if Path(hist_db).exists():
        for e in read_history(hist_db):
            key = (e['id'], e['id'])              # visits are immutable
            if key in seen:
                continue
            seen.add(key); rec = dict(e); rec['hash'] = e['id']; new.append(rec)

    if Path(bm_plist).exists():
        bms, rl = read_bookmarks(bm_plist)
        for e in bms + rl:
            h = content_hash(e['title'], e.get('folder', ''), e.get('date', ''))
            key = (e['id'], h)
            if key in seen:
                continue
            seen.add(key); rec = dict(e); rec['hash'] = h; new.append(rec)

    append_manifest(mpath, new)
    v, b, r = build_views(archive, load_manifest(mpath))
    return {'new': len(new), 'visits': v, 'bookmarks': b, 'readinglist': r}


def main():
    ap = argparse.ArgumentParser(prog='safari_archiver',
        description='Append-only Safari history + bookmarks + reading-list archiver.')
    ap.add_argument('--db', required=True, help='Safari data dir (History.db + Bookmarks.plist)')
    ap.add_argument('--archive', required=True, help='archive root directory')
    ap.add_argument('--version', action='version', version=f'%(prog)s {__version__}')
    a = ap.parse_args()
    if not Path(a.db).exists():
        ap.error(f'Safari data not found: {a.db}')
    r = run_archive(a.db, a.archive)
    print(f'Safari: +{r["new"]} new; {r["visits"]} visits, {r["bookmarks"]} bookmarks, '
          f'{r["readinglist"]} reading-list items.')


if __name__ == '__main__':
    main()
