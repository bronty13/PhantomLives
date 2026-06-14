#!/usr/bin/env python3
# =============================================================================
#   APPLE STICKIES ARCHIVER
#   File:     stickies_archiver.py
#   Version:  1.0.0
#   Requires: Python 3.9+ (stdlib; uses macOS `textutil` for RTF→text when present)
#
#   Permanent, append-only archive of Stickies notes. Each sticky is an `.rtfd`
#   bundle (TXT.rtf + any images); the .rtfd bundles are preserved separately
#   (rsynced into the archive), and this tool extracts their text into per-sticky
#   .txt + a browsable stickies.html. Stickies are mutable → versioned by content.
#
#   Usage:  stickies_archiver.py --db <Stickies dir of *.rtfd> --archive <dir>
# =============================================================================
import argparse
import os
import re
import subprocess
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from applearchive_common import (  # noqa: E402
    s, cd_date, san, short_hash, content_hash,
    load_manifest, manifest_keys, append_manifest, latest_per_id, write_csv,
    html_page, esc,
)

__version__ = '1.0.0'


def _rtf_strip(rtf):
    """Crude pure-Python RTF→text fallback (used only if `textutil` is absent)."""
    t = re.sub(r'\\par[d]?', '\n', rtf)
    t = re.sub(r'\{\\[^}]*\}', '', t)
    t = re.sub(r'\\[a-zA-Z]+-?\d* ?', '', t)
    t = t.replace('{', '').replace('}', '')
    return t.strip()


def extract_text(rtfd):
    """RTFD bundle → plain text. Prefers macOS `textutil`; falls back to a stripper."""
    try:
        out = subprocess.run(['textutil', '-convert', 'txt', '-stdout', str(rtfd)],
                             capture_output=True, timeout=20)
        if out.returncode == 0:
            return out.stdout.decode('utf-8', errors='ignore').strip()
    except (FileNotFoundError, subprocess.SubprocessError):
        pass
    rtf = Path(rtfd) / 'TXT.rtf'
    if rtf.exists():
        try:
            return _rtf_strip(rtf.read_text(encoding='utf-8', errors='ignore'))
        except OSError:
            pass
    return ''


def read_stickies(data_dir):
    out = []
    for rtfd in sorted(Path(data_dir).glob('*.rtfd')):
        text = extract_text(rtfd)
        if not text:
            continue
        title = text.split('\n', 1)[0][:80]
        try:
            modified = datetime.fromtimestamp(
                (rtfd / 'TXT.rtf').stat().st_mtime).strftime('%Y-%m-%d %H:%M')
        except OSError:
            modified = ''
        out.append({'id': rtfd.stem, 'title': title, 'text': text, 'modified': modified})
    return out


def build_views(archive, entries):
    archive = Path(archive)
    notes_dir = archive / 'notes'; notes_dir.mkdir(parents=True, exist_ok=True)
    current = sorted(latest_per_id(entries), key=lambda e: e.get('modified') or '', reverse=True)
    cards, idx = [], []
    for e in current:
        (notes_dir / f'{san(e["title"]) or e["id"]}.txt').write_text(e['text'] + '\n', encoding='utf-8')
        cards.append(f'<div class="item"><div class="t">{esc(e["title"])}</div>'
                     f'<div class="meta">{esc(e["modified"])}</div>'
                     f'<div class="body">{esc(e["text"])}</div></div>')
        idx.append({'title': e['title'], 'modified': e['modified'], 'id': e['id']})
    (archive / 'stickies.html').write_text(
        html_page(f'Stickies ({len(current)})', '\n'.join(cards)), encoding='utf-8')
    write_csv(archive / '_index.csv', ['title', 'modified', 'id'], idx)
    return len(current)


def run_archive(db, archive):
    archive = Path(archive); archive.mkdir(parents=True, exist_ok=True)
    mpath = archive / 'manifest.jsonl'
    seen = manifest_keys(load_manifest(mpath))
    new = []
    for e in read_stickies(db):
        key = (e['id'], content_hash(e['text']))
        if key in seen:
            continue
        seen.add(key); rec = dict(e); rec['hash'] = key[1]; new.append(rec)
    append_manifest(mpath, new)
    total = build_views(archive, load_manifest(mpath))
    return {'new': len(new), 'stickies': total}


def main():
    ap = argparse.ArgumentParser(prog='stickies_archiver',
        description='Append-only Apple Stickies archiver (text from .rtfd bundles).')
    ap.add_argument('--db', required=True, help='dir containing the *.rtfd sticky bundles')
    ap.add_argument('--archive', required=True, help='archive root directory')
    ap.add_argument('--version', action='version', version=f'%(prog)s {__version__}')
    a = ap.parse_args()
    if not Path(a.db).exists():
        ap.error(f'Stickies dir not found: {a.db}')
    r = run_archive(a.db, a.archive)
    print(f'Stickies: +{r["new"]} new version(s); {r["stickies"]} notes.')


if __name__ == '__main__':
    main()
