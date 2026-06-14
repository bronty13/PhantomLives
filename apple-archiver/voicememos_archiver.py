#!/usr/bin/env python3
# =============================================================================
#   APPLE VOICE MEMOS ARCHIVER
#   File:     voicememos_archiver.py
#   Version:  1.0.0
#   Requires: Python 3.9+ (standard library only)
#
#   Permanent, append-only archive of Voice Memos metadata from CloudRecordings.db
#   (ZCLOUDRECORDING: title/date/duration + ZPATH). The audio files themselves
#   (.m4a) are preserved separately (rsynced into <archive>/recordings/); this
#   tool indexes them into a browsable HTML player + CSV. Recordings are mutable
#   (rename/trim), so the manifest versions by (id, content-hash).
#
#   Usage:  voicememos_archiver.py --db <CloudRecordings.db> --archive <dir>
#                                  [--audio-subdir recordings]
# =============================================================================
import argparse
import os
import re
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from applearchive_common import (  # noqa: E402
    open_ro, rows, has_table, s, cd_date, short_hash, content_hash,
    load_manifest, manifest_keys, append_manifest, latest_per_id, write_csv,
    html_page, esc,
)

__version__ = '1.0.0'


def _dur(seconds):
    try:
        sec = int(float(seconds or 0))
    except (TypeError, ValueError):
        return ''
    m, s2 = sec // 60, sec % 60
    return f'{m}:{s2:02d}' if sec > 0 else ''


def _fname_date(stem):
    """Voice-memo filenames look like '20260126 134059-A88E2888' → 2026-01-26 13:40."""
    m = re.match(r'(\d{8})\s+(\d{6})', stem)
    if not m:
        return ''
    d, t = m.group(1), m.group(2)
    return f'{d[:4]}-{d[4:6]}-{d[6:8]} {t[:2]}:{t[2:4]}'


def read_memos(db, archive, audio_subdir):
    """File-driven: every .m4a in the archive is a memo; CloudRecordings.db (often
    empty) enriches with the user's title + duration when present."""
    by_id = {}
    if db and Path(db).exists():
        conn = open_ro(db)
        if has_table(conn, 'ZCLOUDRECORDING'):
            for label, path, dur, date in rows(conn,
                    'SELECT ZCUSTOMLABEL, ZPATH, ZDURATION, ZDATE FROM ZCLOUDRECORDING'):
                fname = Path(s(path)).name if path else ''
                if not fname:
                    continue
                by_id[fname] = {'id': fname, 'title': s(label) or fname.rsplit('.', 1)[0],
                                'audio': f'{audio_subdir}/{fname}', 'duration': _dur(dur),
                                'date': cd_date(date, '%Y-%m-%d %H:%M')}
        conn.close()
    adir = Path(archive) / audio_subdir
    for f in sorted(adir.glob('*.m4a')):
        if f.name in by_id:
            continue
        by_id[f.name] = {'id': f.name, 'title': f.stem,
                         'audio': f'{audio_subdir}/{f.name}', 'duration': '',
                         'date': _fname_date(f.stem)}
    return list(by_id.values())


def build_views(archive, entries, audio_subdir):
    archive = Path(archive)
    current = sorted(latest_per_id(entries), key=lambda e: e.get('date') or '', reverse=True)
    cards, csv_rows = [], []
    for e in current:
        present = e['audio'] and (archive / e['audio']).exists()
        player = (f'<audio controls preload="none" src="{esc(e["audio"])}"></audio>'
                  if present else '<div class="sub">(audio not in archive yet)</div>')
        cards.append(f'<div class="item"><div class="t">{esc(e["title"])}</div>'
                     f'<div class="meta">{esc(e["date"])}'
                     f'{" · " + esc(e["duration"]) if e["duration"] else ""}</div>{player}</div>')
        csv_rows.append({'title': e['title'], 'date': e['date'],
                         'duration': e['duration'], 'file': e['audio'] or ''})
    (archive / 'voicememos.html').write_text(
        html_page(f'Voice Memos ({len(current)})', '\n'.join(cards)), encoding='utf-8')
    write_csv(archive / '_index.csv', ['title', 'date', 'duration', 'file'], csv_rows)
    return len(current)


def run_archive(db, archive, audio_subdir='recordings'):
    archive = Path(archive); archive.mkdir(parents=True, exist_ok=True)
    mpath = archive / 'manifest.jsonl'
    seen = manifest_keys(load_manifest(mpath))
    new = []
    for e in read_memos(db, archive, audio_subdir):
        key = (e['id'], content_hash(e['title'], e['duration'], e['date']))
        if key in seen:
            continue
        seen.add(key)
        rec = dict(e); rec['hash'] = key[1]
        new.append(rec)
    append_manifest(mpath, new)
    total = build_views(archive, load_manifest(mpath), audio_subdir)
    return {'new': len(new), 'memos': total}


def main():
    ap = argparse.ArgumentParser(prog='voicememos_archiver',
        description='Append-only Apple Voice Memos archiver (metadata + HTML player).')
    ap.add_argument('--db', default=None,
                    help='path to CloudRecordings.db (optional — files drive the archive)')
    ap.add_argument('--archive', required=True, help='archive root directory')
    ap.add_argument('--audio-subdir', default='recordings',
                    help='subdir under the archive where .m4a files are mirrored')
    ap.add_argument('--version', action='version', version=f'%(prog)s {__version__}')
    a = ap.parse_args()
    r = run_archive(a.db, a.archive, audio_subdir=a.audio_subdir)
    print(f'Voice Memos: +{r["new"]} new version(s); {r["memos"]} recordings.')


if __name__ == '__main__':
    main()
