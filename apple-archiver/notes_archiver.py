#!/usr/bin/env python3
# =============================================================================
#   APPLE NOTES ARCHIVER
#   File:     notes_archiver.py
#   Version:  1.1.0
#   Requires: Python 3.9+ (standard library only)
#
#   Permanent, append-only, browsable archive of Apple Notes from a
#   NoteStore.sqlite (a pulled snapshot is fine). Note bodies are stored as a
#   gzip-compressed protobuf in ZICNOTEDATA.ZDATA; this decodes them with a small
#   pure-Python protobuf walker (no external deps).
#
#   Notes are MUTABLE, so the manifest appends a new version whenever a note's
#   text changes (keyed by note id + content-hash) — edits and deletions are
#   preserved forever. Views (text + HTML + index) are regenerated each run from
#   the latest version of each note.
#
#   Usage:  notes_archiver.py --db <NoteStore.sqlite> --archive <dir>
# =============================================================================
import argparse
import gzip
import html
import os
import sys
from collections import defaultdict
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from applearchive_common import (  # noqa: E402
    open_ro, rows, s, cd_date, san, slug, short_hash, content_hash,
    load_manifest, manifest_keys, append_manifest, latest_per_id, write_csv,
    html_page, esc,
)

__version__ = '1.1.0'


def decode_note_body(blob):
    """Decode an Apple Notes ZDATA blob (gzip → protobuf) to plain text.

    Walks the protobuf for length-delimited UTF-8 fields and returns the longest
    one (the note's text run). Returns '' on failure."""
    try:
        data = gzip.decompress(bytes(blob))
    except (OSError, EOFError, ValueError):
        return ''

    found = []

    def walk(buf):
        i = 0
        while i < len(buf):
            tag = buf[i]; i += 1
            wt = tag & 7
            if wt == 2:                                  # length-delimited
                ln = 0; sh = 0
                while i < len(buf):
                    b = buf[i]; i += 1
                    ln |= (b & 0x7f) << sh; sh += 7
                    if not b & 0x80:
                        break
                chunk = buf[i:i + ln]; i += ln
                try:
                    txt = chunk.decode('utf-8')
                    if txt and (txt.isprintable() or '\n' in txt or '\t' in txt):
                        found.append(txt)
                    else:
                        walk(chunk)
                except UnicodeDecodeError:
                    walk(chunk)                           # nested message
            elif wt == 0:                                 # varint
                while i < len(buf) and buf[i] & 0x80:
                    i += 1
                i += 1
            elif wt == 5:
                i += 4
            elif wt == 1:
                i += 8
            else:
                return
    walk(data)
    if not found:
        return ''
    return max(found, key=len).replace('￼', '').rstrip()


def read_notes(db):
    conn = open_ro(db)
    # Folder titles live on their own rows (ZTITLE2); notes point at them via ZFOLDER.
    folders = {pk: s(t) for pk, t in rows(conn,
               'SELECT Z_PK, ZTITLE2 FROM ZICCLOUDSYNCINGOBJECT WHERE ZTITLE2 IS NOT NULL')}
    # Any row's Z_PK → its ZIDENTIFIER (media objects' identifier == their on-disk
    # Media/<uuid>/ folder name).
    pk_ident = {pk: s(i) for pk, i in rows(conn,
                'SELECT Z_PK, ZIDENTIFIER FROM ZICCLOUDSYNCINGOBJECT WHERE ZIDENTIFIER IS NOT NULL')}
    # Attachments: rows with a parent note (ZNOTE) + a type. ZMEDIA → media object
    # whose identifier locates the file on disk.
    atts_by_note = defaultdict(list)
    for note_pk, media_pk, uti, fname in rows(conn,
            'SELECT ZNOTE, ZMEDIA, ZTYPEUTI, ZFILENAME FROM ZICCLOUDSYNCINGOBJECT '
            'WHERE ZNOTE IS NOT NULL AND ZTYPEUTI IS NOT NULL'):
        atts_by_note[note_pk].append({
            'uti': s(uti), 'media': pk_ident.get(media_pk, ''),
            'filename': s(fname), 'path': None,
        })

    out = []
    # Date columns vary by macOS version; COALESCE the known variants.
    for r in rows(conn,
            'SELECT o.Z_PK, o.ZIDENTIFIER, o.ZTITLE1, o.ZFOLDER, '
            '       COALESCE(o.ZCREATIONDATE3, o.ZCREATIONDATE1, o.ZCREATIONDATE), '
            '       COALESCE(o.ZMODIFICATIONDATE1, o.ZMODIFICATIONDATE), '
            '       o.ZMARKEDFORDELETION, d.ZDATA '
            'FROM ZICCLOUDSYNCINGOBJECT o '
            'JOIN ZICNOTEDATA d ON d.Z_PK = o.ZNOTEDATA '
            'WHERE o.ZNOTEDATA IS NOT NULL'):
        pk, ident, title, folder_pk, created, modified, deleted, data = r
        nid = s(ident) or short_hash(title, created)
        body = decode_note_body(data) if data else ''
        out.append({
            'id': nid,
            'title': s(title) or (body.split('\n', 1)[0][:80] if body else 'Untitled'),
            'folder': folders.get(folder_pk, 'Notes'),
            'created': cd_date(created), 'modified': cd_date(modified),
            'deleted': bool(deleted),
            'body': body,
            'attachments': [a for a in atts_by_note.get(pk, []) if a['media']],
        })
    conn.close()
    return out


def _att_kind(uti):
    u = (uti or '').lower()
    if 'image' in u or u.endswith(('heic', 'jpeg', 'jpg', 'png', 'gif', 'tiff', 'webp')) \
            or u == 'com.compuserve.gif':
        return 'image'
    if 'audio' in u or 'm4a' in u or 'caf' in u:
        return 'audio'
    return 'file'


def build_media_index(archive, media_subdir, wanted):
    """Map each wanted media-uuid → the (largest) archived file under it."""
    root = archive / media_subdir
    idx = {}
    if not wanted or not root.exists():
        return idx
    for f in root.rglob('*'):
        if not f.is_file():
            continue
        hit = set(f.relative_to(archive).parts) & wanted
        if not hit:
            continue
        u = next(iter(hit))
        try:
            sz = f.stat().st_size
        except OSError:
            sz = 0
        if u not in idx or sz > idx[u][1]:
            idx[u] = (str(f.relative_to(archive)), sz)
    return {u: v[0] for u, v in idx.items()}


def build_views(archive, entries, media_subdir='media'):
    archive = Path(archive)
    notes_root = archive / 'notes'
    notes_root.mkdir(parents=True, exist_ok=True)

    versions = {}
    for e in entries:
        versions[e['id']] = versions.get(e['id'], 0) + 1

    current = latest_per_id(entries)
    current.sort(key=lambda e: e.get('modified') or '', reverse=True)

    wanted = {a['media'] for e in current for a in e.get('attachments', []) if a.get('media')}
    media_index = build_media_index(archive, media_subdir, wanted)
    n_media = 0

    index_rows, cards = [], []
    for e in current:
        atts = e.get('attachments', [])
        for a in atts:
            a['path'] = media_index.get(a.get('media'))
        present = [a for a in atts if a.get('path')]
        n_media += len(present)

        folder = san(e['folder'])
        d = notes_root / folder
        d.mkdir(parents=True, exist_ok=True)
        fname = f"{slug(e['title'])}__{short_hash(e['id'])}.md"
        header = [f"# {e['title']}", '',
                  f"_Folder: {e['folder']}  ·  Created: {e['created']}  ·  "
                  f"Modified: {e['modified']}  ·  Versions: {versions[e['id']]}"
                  f"{'  ·  DELETED on source' if e['deleted'] else ''}_", '', '---', '']
        md = '\n'.join(header) + (e['body'] or '_(empty)_') + '\n'
        if present:
            md += '\n\n## Attachments\n'
            for a in present:
                md += f"- [{a['filename'] or a['uti']}](../../{a['path']})\n"
        (d / fname).write_text(md, encoding='utf-8')

        rel = f"notes/{folder}/{fname}"
        index_rows.append({'title': e['title'], 'folder': e['folder'],
                           'created': e['created'], 'modified': e['modified'],
                           'versions': versions[e['id']], 'attachments': len(present),
                           'deleted': 'yes' if e['deleted'] else '', 'file': rel})
        media_html = ''
        for a in present:
            k, p = _att_kind(a['uti']), esc(a['path'])
            if k == 'image':
                media_html += f'<img src="{p}" loading="lazy" style="max-width:240px;border-radius:8px;margin:4px 6px 0 0">'
            elif k == 'audio':
                media_html += f'<audio controls preload="none" src="{p}"></audio>'
            else:
                media_html += f'<a href="{p}">📎 {esc(a["filename"] or a["uti"])}</a><br>'
        snippet = (e['body'] or '')[:200]
        cls = 't done' if e['deleted'] else 't'
        cards.append(
            f'<div class="item"><div class="{cls}"><a href="{esc(rel)}">{esc(e["title"])}</a></div>'
            f'<div class="meta">{esc(e["folder"])} · {esc(e["modified"])}'
            f'{" · DELETED" if e["deleted"] else ""} · v{versions[e["id"]]}'
            f'{" · " + str(len(present)) + " attachment(s)" if present else ""}</div>'
            f'<div class="body">{esc(snippet)}</div>{media_html}</div>')

    (archive / 'notes.html').write_text(
        html_page(f'Notes ({len(current)})', '\n'.join(cards)), encoding='utf-8')
    write_csv(archive / '_index.csv',
              ['title', 'folder', 'created', 'modified', 'versions', 'attachments', 'deleted', 'file'],
              index_rows)
    return len(current), n_media


def run_archive(db, archive, media_subdir='media'):
    archive = Path(archive)
    archive.mkdir(parents=True, exist_ok=True)
    mpath = archive / 'manifest.jsonl'
    existing = load_manifest(mpath)
    seen = manifest_keys(existing)

    new = []
    for e in read_notes(db):
        att_sig = ','.join(sorted(a['media'] for a in e.get('attachments', [])))
        key = (e['id'], content_hash(e['title'], e['body'], att_sig))
        if key in seen:
            continue
        seen.add(key)
        rec = dict(e); rec['hash'] = key[1]
        new.append(rec)
    append_manifest(mpath, new)

    notes, media = build_views(archive, load_manifest(mpath), media_subdir)
    return {'new_versions': len(new), 'notes': notes, 'media': media}


def main():
    ap = argparse.ArgumentParser(prog='notes_archiver',
        description='Append-only, browsable Apple Notes archiver.')
    ap.add_argument('--db', required=True, help='path to a NoteStore.sqlite (snapshot is fine)')
    ap.add_argument('--archive', required=True, help='archive root directory')
    ap.add_argument('--media-subdir', default='media',
                    help='subdir under the archive where the Notes Media tree is mirrored')
    ap.add_argument('--version', action='version', version=f'%(prog)s {__version__}')
    a = ap.parse_args()
    if not Path(a.db).exists():
        ap.error(f'NoteStore.sqlite not found: {a.db}')
    r = run_archive(a.db, a.archive, media_subdir=a.media_subdir)
    print(f'Notes archive: +{r["new_versions"]} new version(s); {r["notes"]} notes total; '
          f'{r["media"]} attachment(s) linked.')


if __name__ == '__main__':
    main()
