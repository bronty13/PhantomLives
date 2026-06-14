#!/usr/bin/env python3
# =============================================================================
#
#   MESSAGES ARCHIVER  (companion to export_messages.py)
#
#   File:     archive_messages.py
#   Version:  1.4.0
#   License:  MIT
#   Requires: Python 3.9+ (standard library only — NO Pillow/ffmpeg/exiftool)
#
#   Description:
#     Builds a PERMANENT, APPEND-ONLY archive of EVERY iMessage conversation
#     from a chat.db. Where export_messages.py is a one-shot, per-contact, full
#     re-export (copying + sanitizing attachments), this tool is designed to run
#     INCREMENTALLY against a (possibly pulled) chat.db snapshot:
#
#       • enumerates ALL chats, not one contact;
#       • appends only messages newer than the last run (watermark on
#         message.date) AND de-duplicated by message GUID, so re-runs add
#         nothing (idempotent);
#       • writes per-conversation transcripts + a master manifest.jsonl — one
#         JSON line per message GUID, the "nothing ever lost" record;
#       • REFERENCES attachment files by their path under <archive>/attachments/
#         (the media bytes are mirrored separately by rsync). This tool never
#         copies, converts, or mutates attachments, and never deletes anything.
#
#     Preservation guarantee: append-only. Messages or attachments deleted on
#     the source device remain in the archive forever.
#
#   Reuses the hard parts from export_messages.py: get_body (attributedBody
#   NSKeyedArchiver decode), mts (Mac-epoch -> datetime), knd (attachment
#   classification), san/slug (filesystem-safe names).
#
#   Usage:
#     archive_messages.py --db <chat.db> --archive <dir> [--full]
#                         [--attachments-subdir attachments]
#
# =============================================================================
import argparse
import json
import os
import sqlite3
import sys
from pathlib import Path

# Import the proven internals from the sibling exporter (import-safe: its
# optional deps are try/except-guarded and main() is __main__-guarded).
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from export_messages import get_body, mts, knd, san, slug  # noqa: E402

__version__ = '1.4.0'

# chat.db attachment.filename values look like
#   ~/Library/Messages/Attachments/ab/12/<guid>/IMG_0001.HEIC
# The media is mirrored to <archive>/<attachments-subdir>/ preserving the path
# *under* "Attachments/", so we map by splitting on this marker.
ATTACH_MARKER = '/Attachments/'


def chat_folder(display_name, chat_identifier, chat_guid):
    """Stable, human-ish folder name for a conversation.

    Prefers the group display name, else the chat identifier (the handle for a
    1:1). A short suffix from the (stable) chat GUID disambiguates same-named
    chats and keeps the folder stable even if a group is later renamed.
    """
    label = (display_name or '').strip() or (chat_identifier or '').strip() or 'chat'
    base = slug(label, mode='strip', mx=60)
    if base == 'NO_TEXT':
        base = 'chat'
    suffix = san((chat_guid or chat_identifier or 'x').split('/')[-1])[-12:]
    return f'{base}__{suffix}'


def rel_attachment_path(filename, attach_subdir):
    """Map a chat.db attachment.filename to its path under the archive.

    Returns e.g. 'attachments/ab/12/<guid>/IMG.HEIC', or None if unmappable.
    """
    if not filename:
        return None
    i = filename.find(ATTACH_MARKER)
    if i == -1:
        # Fall back to just the leaf name under the subdir.
        return f'{attach_subdir}/{Path(filename).name}'
    return attach_subdir + '/' + filename[i + len(ATTACH_MARKER):]


def load_state(archive):
    """Read the incremental watermark. Returns {'last_date': int}."""
    p = Path(archive) / 'state.json'
    try:
        return json.loads(p.read_text(encoding='utf-8'))
    except (OSError, json.JSONDecodeError):
        return {'last_date': 0}


def save_state(archive, last_date, total):
    p = Path(archive) / 'state.json'
    p.write_text(json.dumps({'last_date': int(last_date), 'messages': int(total)},
                            indent=2), encoding='utf-8')


def load_seen_guids(manifest_path):
    """Collect GUIDs already in the manifest so re-runs never duplicate a
    message even if the watermark is reset (e.g. --full)."""
    seen = set()
    p = Path(manifest_path)
    if not p.exists():
        return seen
    with p.open(encoding='utf-8') as fh:
        for line in fh:
            line = line.strip()
            if not line:
                continue
            try:
                g = json.loads(line).get('guid')
                if g:
                    seen.add(g)
            except json.JSONDecodeError:
                continue
    return seen


def fetch_attachments(conn, message_rowid):
    rows = conn.execute(
        'SELECT a.filename, a.mime_type, a.transfer_name '
        'FROM attachment a '
        'JOIN message_attachment_join maj ON maj.attachment_id=a.ROWID '
        'WHERE maj.message_id=?', (message_rowid,)).fetchall()
    return rows


def run_archive(db, archive, attach_subdir='attachments', full=False):
    """Append all new messages from `db` into the append-only archive at
    `archive`. Returns a summary dict."""
    archive = Path(archive)
    conv_dir = archive / 'conversations'
    conv_dir.mkdir(parents=True, exist_ok=True)
    manifest_path = archive / 'manifest.jsonl'

    state = {'last_date': 0} if full else load_state(archive)
    watermark = int(state.get('last_date', 0) or 0)
    seen = load_seen_guids(manifest_path)

    conn = sqlite3.connect(f'file:{db}?mode=ro', uri=True)
    conn.row_factory = sqlite3.Row

    # One row per message (GROUP BY guards against duplicate chat_message_join
    # rows), across ALL chats, newer than the watermark, in chronological order.
    q = (
        'SELECT m.ROWID AS rowid, m.guid AS guid, m.date AS date, '
        '       m.is_from_me AS is_from_me, m.text AS text, '
        '       m.attributedBody AS ab, h.id AS handle_id, '
        '       c.guid AS chat_guid, c.chat_identifier AS chat_identifier, '
        '       c.display_name AS display_name '
        'FROM message m '
        'JOIN chat_message_join cmj ON cmj.message_id=m.ROWID '
        'JOIN chat c ON c.ROWID=cmj.chat_id '
        'LEFT JOIN handle h ON h.ROWID=m.handle_id '
        'WHERE m.date > ? '
        'GROUP BY m.ROWID ORDER BY m.date'
    )
    rows = conn.execute(q, (watermark,)).fetchall()

    transcripts = {}            # folder -> list of lines to append this run
    new_entries = []            # manifest lines (dicts) to append this run
    max_date = watermark
    n_msgs = n_att = 0
    convos = set()

    for m in rows:
        guid = m['guid']
        if not guid or guid in seen:
            continue
        seen.add(guid)

        date_raw = int(m['date'] or 0)
        max_date = max(max_date, date_raw)
        try:
            dt = mts(date_raw).astimezone()
            ts = dt.isoformat()
            ts_h = dt.strftime('%Y-%m-%d %H:%M:%S')
        except (ValueError, OverflowError, OSError):
            ts = ts_h = ''
        sender = 'Me' if m['is_from_me'] else (m['handle_id'] or m['chat_identifier'] or '?')
        body = get_body(m['text'], m['ab'])

        folder = chat_folder(m['display_name'], m['chat_identifier'], m['chat_guid'])
        convos.add(folder)

        atts = []
        for a in fetch_attachments(conn, m['rowid']):
            fname, mime, xfer = a['filename'], a['mime_type'], a['transfer_name']
            ext = Path(xfer or fname or '').suffix.lower()
            atts.append({
                'orig': xfer or (Path(fname).name if fname else None),
                'mime': mime,
                'kind': knd(mime, ext),
                'path': rel_attachment_path(fname, attach_subdir),
            })
            n_att += 1

        # Transcript line(s) for this message.
        line = f'[{ts_h}] {sender}:'
        if body:
            line += f' {body}'
        lines = [line]
        for at in atts:
            lines.append(f'    [{at["kind"]}] {at["orig"] or "?"} -> {at["path"] or "MISSING"}')
        transcripts.setdefault(folder, []).append('\n'.join(lines))

        new_entries.append({
            'guid': guid, 'ts': ts, 'date_raw': date_raw,
            'chat': (m['display_name'] or m['chat_identifier'] or ''),
            'chat_id': m['chat_identifier'], 'sender': sender,
            'from_me': int(m['is_from_me'] or 0), 'text': body,
            'attachments': atts,
        })
        n_msgs += 1

    conn.close()

    # Append (never rewrite) — transcripts per conversation, then the manifest.
    for folder, lines in transcripts.items():
        d = conv_dir / folder
        d.mkdir(parents=True, exist_ok=True)
        with (d / 'transcript.txt').open('a', encoding='utf-8') as fh:
            fh.write('\n'.join(lines) + '\n')

    if new_entries:
        with manifest_path.open('a', encoding='utf-8') as fh:
            for e in new_entries:
                fh.write(json.dumps(e, ensure_ascii=False) + '\n')

    total = len(seen)
    save_state(archive, max_date, total)

    return {
        'appended': n_msgs, 'attachments': n_att,
        'conversations_touched': len(convos), 'total_messages': total,
        'last_date': max_date,
    }


def main():
    ap = argparse.ArgumentParser(
        prog='archive_messages',
        description='Append-only, all-conversations Apple Messages archiver.')
    ap.add_argument('--db', required=True, help='path to a chat.db (snapshot is fine)')
    ap.add_argument('--archive', required=True, help='archive root directory')
    ap.add_argument('--attachments-subdir', default='attachments',
                    help='subdir under the archive where media is mirrored '
                         '(default: attachments)')
    ap.add_argument('--full', action='store_true',
                    help='ignore the incremental watermark and re-scan the whole '
                         'db (still de-duplicated by message GUID)')
    ap.add_argument('--version', action='version', version=f'%(prog)s {__version__}')
    a = ap.parse_args()

    if not Path(a.db).exists():
        ap.error(f'chat.db not found: {a.db}')

    r = run_archive(a.db, a.archive, attach_subdir=a.attachments_subdir, full=a.full)
    print(f'Messages archive: appended {r["appended"]} new message(s) '
          f'({r["attachments"]} attachment refs) across '
          f'{r["conversations_touched"]} conversation(s); '
          f'archive now holds {r["total_messages"]} message(s).')


if __name__ == '__main__':
    main()
