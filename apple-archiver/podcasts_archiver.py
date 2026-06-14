#!/usr/bin/env python3
# =============================================================================
#   APPLE PODCASTS ARCHIVER
#   File:     podcasts_archiver.py
#   Version:  1.0.0
#   Requires: Python 3.9+ (standard library only)
#
#   Permanent, append-only archive of Apple Podcasts subscriptions from
#   MTLibrary.sqlite (ZMTPODCAST + ZMTEPISODE). Subscriptions are mutable, so the
#   manifest versions by (id, content-hash). Outputs podcasts.html + _index.csv.
#
#   Usage:  podcasts_archiver.py --db <MTLibrary.sqlite> --archive <dir>
# =============================================================================
import argparse
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from applearchive_common import (  # noqa: E402
    open_ro, rows, has_table, s, short_hash, content_hash,
    load_manifest, manifest_keys, append_manifest, latest_per_id, write_csv,
    html_page, esc,
)

__version__ = '1.0.0'


def read_podcasts(db):
    conn = open_ro(db)
    if not has_table(conn, 'ZMTPODCAST'):
        conn.close(); return []
    # Episode counts per podcast.
    ep = {}
    if has_table(conn, 'ZMTEPISODE'):
        for pk, c in rows(conn, 'SELECT ZPODCAST, COUNT(*) FROM ZMTEPISODE GROUP BY ZPODCAST'):
            ep[pk] = c
    out = []
    for pk, title, author, feed, web, cat, sub in rows(conn,
            'SELECT Z_PK, ZTITLE, ZAUTHOR, ZFEEDURL, ZWEBPAGEURL, ZCATEGORY, ZSUBSCRIBED '
            'FROM ZMTPODCAST WHERE ZTITLE IS NOT NULL'):
        out.append({
            'id': short_hash(s(title)), 'title': s(title), 'author': s(author),
            'feed': s(feed), 'website': s(web), 'category': s(cat),
            'subscribed': bool(sub), 'episodes': ep.get(pk, 0),
        })
    conn.close()
    return out


def build_views(archive, entries):
    archive = Path(archive)
    current = sorted(latest_per_id(entries), key=lambda e: e['title'].lower())
    cards, idx = [], []
    for e in current:
        link = e['website'] or e['feed']
        title = (f'<a href="{esc(link)}">{esc(e["title"])}</a>' if link else esc(e['title']))
        meta = ' · '.join(x for x in [e['author'], e['category'],
                                      f'{e["episodes"]} episodes' if e['episodes'] else '',
                                      '' if e['subscribed'] else 'not subscribed'] if x)
        cards.append(f'<div class="item"><div class="t">{title}</div>'
                     f'<div class="meta">{esc(meta)}</div></div>')
        idx.append({'title': e['title'], 'author': e['author'], 'category': e['category'],
                    'episodes': e['episodes'], 'subscribed': 'yes' if e['subscribed'] else 'no',
                    'feed': e['feed']})
    (archive / 'podcasts.html').write_text(
        html_page(f'Podcasts ({len(current)})', '\n'.join(cards)), encoding='utf-8')
    write_csv(archive / '_index.csv',
              ['title', 'author', 'category', 'episodes', 'subscribed', 'feed'], idx)
    return len(current)


def run_archive(db, archive):
    archive = Path(archive); archive.mkdir(parents=True, exist_ok=True)
    mpath = archive / 'manifest.jsonl'
    seen = manifest_keys(load_manifest(mpath))
    new = []
    for e in read_podcasts(db):
        key = (e['id'], content_hash(e['title'], e['author'], e['feed'], e['subscribed']))
        if key in seen:
            continue
        seen.add(key); rec = dict(e); rec['hash'] = key[1]; new.append(rec)
    append_manifest(mpath, new)
    total = build_views(archive, load_manifest(mpath))
    return {'new': len(new), 'podcasts': total}


def main():
    ap = argparse.ArgumentParser(prog='podcasts_archiver',
        description='Append-only Apple Podcasts subscriptions archiver.')
    ap.add_argument('--db', required=True, help='path to MTLibrary.sqlite')
    ap.add_argument('--archive', required=True, help='archive root directory')
    ap.add_argument('--version', action='version', version=f'%(prog)s {__version__}')
    a = ap.parse_args()
    if not Path(a.db).exists():
        ap.error(f'MTLibrary.sqlite not found: {a.db}')
    r = run_archive(a.db, a.archive)
    print(f'Podcasts: +{r["new"]} new version(s); {r["podcasts"]} shows.')


if __name__ == '__main__':
    main()
