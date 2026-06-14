#!/usr/bin/env python3
# =============================================================================
#   APPLE CALL HISTORY ARCHIVER
#   File:     callhistory_archiver.py
#   Version:  1.0.0
#   Requires: Python 3.9+ (standard library only)
#
#   Permanent, append-only archive of phone + FaceTime call history from
#   CallHistory.storedata (Core Data: ZCALLRECORD). Calls are immutable events,
#   so the manifest is keyed by (address, date) and only grows.
#
#   Usage:  callhistory_archiver.py --db <CallHistory.storedata> --archive <dir>
# =============================================================================
import argparse
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from applearchive_common import (  # noqa: E402
    open_ro, rows, has_table, s, cd_date, short_hash,
    load_manifest, manifest_keys, append_manifest, write_csv, html_page, esc,
)

__version__ = '1.0.1'

CALL_TYPE = {1: 'Phone', 8: 'FaceTime', 16: 'FaceTime Video'}


def _addr(v):
    """ZADDRESS/ZNAME are plaintext on some macOS versions but ENCRYPTED blobs on
    others (notably ≤12). Return a clean string, or '(encrypted)' for blobs we
    can't read — never raw bytes."""
    if v is None:
        return ''
    if isinstance(v, (bytes, bytearray)):
        try:
            t = bytes(v).decode('utf-8')
        except UnicodeDecodeError:
            return '(encrypted)'
        return t.strip() if (t.strip() and t.isprintable()) else '(encrypted)'
    return str(v).strip()


def _dur(seconds):
    try:
        sec = int(float(seconds or 0))
    except (TypeError, ValueError):
        return ''
    if sec <= 0:
        return ''
    h, m, s2 = sec // 3600, (sec % 3600) // 60, sec % 60
    return (f'{h}:{m:02d}:{s2:02d}' if h else f'{m}:{s2:02d}')


def read_calls(db):
    conn = open_ro(db)
    if not has_table(conn, 'ZCALLRECORD'):
        conn.close(); return []
    out = []
    for addr, name, orig, ctype, answered, dur, date, svc in rows(conn,
            'SELECT ZADDRESS, ZNAME, ZORIGINATED, ZCALLTYPE, ZANSWERED, '
            '       ZDURATION, ZDATE, ZSERVICE_PROVIDER FROM ZCALLRECORD'):
        when = cd_date(date, '%Y-%m-%d %H:%M:%S')
        addr_s = _addr(addr)
        name_s = _addr(name)
        out.append({
            'id': short_hash(addr_s, when),
            'address': addr_s, 'name': name_s if name_s != '(encrypted)' else '',
            'direction': 'outgoing' if orig else 'incoming',
            'kind': CALL_TYPE.get(int(ctype or 0), 'Call'),
            'answered': bool(answered),
            'missed': bool(not answered and not orig),
            'duration': _dur(dur), 'date': when, 'service': s(svc),
        })
    conn.close()
    return out


def build_views(archive, entries):
    archive = Path(archive)
    entries = sorted(entries, key=lambda e: e.get('date') or '', reverse=True)

    # Per-call HTML + CSV.
    cards, csv_rows = [], []
    by_addr = {}
    for e in entries:
        who = e['name'] or e['address'] or 'Unknown'
        arrow = '↗' if e['direction'] == 'outgoing' else ('↙' if e['answered'] else '✖')
        miss = ' missed' if e['missed'] else ''
        meta = ' · '.join(x for x in [e['kind'], e['duration'], e['service']] if x)
        cards.append(f'<div class="item{miss}"><div class="t">{arrow} {esc(who)}'
                     f'{" (missed)" if e["missed"] else ""}</div>'
                     f'<div class="meta">{esc(e["date"])} · {esc(meta)}'
                     f'{" · " + esc(e["address"]) if e["name"] else ""}</div></div>')
        csv_rows.append({'date': e['date'], 'who': who, 'address': e['address'],
                         'direction': e['direction'], 'kind': e['kind'],
                         'answered': 'yes' if e['answered'] else 'no',
                         'duration': e['duration']})
        a = by_addr.setdefault(e['address'] or 'Unknown',
                               {'name': e['name'], 'calls': 0, 'missed': 0})
        a['calls'] += 1; a['missed'] += 1 if e['missed'] else 0
        if e['name'] and not a['name']:
            a['name'] = e['name']

    (archive / 'calls.html').write_text(
        html_page(f'Call history ({len(entries)})', '\n'.join(cards)), encoding='utf-8')
    write_csv(archive / 'calls.csv',
              ['date', 'who', 'address', 'direction', 'kind', 'answered', 'duration'], csv_rows)
    idx = [{'who': v['name'] or k, 'address': k, 'calls': v['calls'], 'missed': v['missed']}
           for k, v in sorted(by_addr.items(), key=lambda kv: kv[1]['calls'], reverse=True)]
    write_csv(archive / '_index.csv', ['who', 'address', 'calls', 'missed'], idx)
    return len(entries)


def run_archive(db, archive):
    archive = Path(archive); archive.mkdir(parents=True, exist_ok=True)
    mpath = archive / 'manifest.jsonl'
    seen = manifest_keys(load_manifest(mpath))
    new = []
    for e in read_calls(db):
        key = (e['id'], e['id'])     # calls are immutable; id alone identifies them
        if key in seen:
            continue
        seen.add(key)
        rec = dict(e); rec['hash'] = e['id']
        new.append(rec)
    append_manifest(mpath, new)
    total = build_views(archive, load_manifest(mpath))
    return {'new': len(new), 'calls': total}


def main():
    ap = argparse.ArgumentParser(prog='callhistory_archiver',
        description='Append-only Apple call-history archiver.')
    ap.add_argument('--db', required=True, help='path to CallHistory.storedata')
    ap.add_argument('--archive', required=True, help='archive root directory')
    ap.add_argument('--version', action='version', version=f'%(prog)s {__version__}')
    a = ap.parse_args()
    if not Path(a.db).exists():
        ap.error(f'CallHistory.storedata not found: {a.db}')
    r = run_archive(a.db, a.archive)
    print(f'Call history: +{r["new"]} new call(s); {r["calls"]} total.')


if __name__ == '__main__':
    main()
