#!/usr/bin/env python3
# =============================================================================
#
#   MESSAGES ARCHIVER  (companion to export_messages.py)
#
#   File:     archive_messages.py
#   Version:  1.5.0
#   License:  MIT
#   Requires: Python 3.9+ (standard library only — NO Pillow/ffmpeg/exiftool)
#
#   Builds a PERMANENT, APPEND-ONLY, HUMAN-BROWSABLE archive of EVERY iMessage
#   conversation from a chat.db, designed to run incrementally.
#
#   Source of truth (append-only, never rewritten):
#     • manifest.jsonl   — one JSON line per message GUID (the "nothing ever
#                          lost" record). Grows only; de-duplicated by GUID.
#     • attachments/      — the raw media byte-store (mirrored separately, e.g.
#                          by rsync). This tool never deletes from it.
#
#   Human-facing views (DERIVED — regenerated from manifest.jsonl each run, so
#   the layout can improve without risking the source of truth):
#     • conversations/<Name>/transcript.txt   — readable, contact names resolved
#     • conversations/<Name>/index.html       — Messages-style bubbles + media
#     • conversations/<Name>/media/           — that thread's photos/videos/files,
#                                               REAL COPIES, date-prefixed names
#     • _index.csv                            — who / folder / #msgs / dates / #media
#
#   Contact names are resolved from a (pulled) AddressBook via --addressbook-dir;
#   unknown handles stay as the raw number/email.
#
#   Reuses export_messages internals: get_body (attributedBody decode), mts,
#   knd, san, slug, norm.
#
#   Usage:
#     archive_messages.py --db <chat.db> --archive <dir>
#                         [--addressbook-dir <Sources dir>] [--full]
#
# =============================================================================
import argparse
import csv
import hashlib
import html
import json
import os
import shutil
import sqlite3
import sys
from collections import defaultdict
from datetime import datetime
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from export_messages import get_body, mts, knd, san, slug, norm  # noqa: E402

__version__ = '1.6.0'

ATTACH_MARKER = '/Attachments/'


# ─── Contact resolution ──────────────────────────────────────────────────────

def load_contacts(ab_dir):
    """Build a {normalized-handle -> display name} map from AddressBook .abcddb
    files under `ab_dir` (a pulled `.../AddressBook/Sources` directory). Phones
    are keyed by last-10-digits (norm); emails by lowercase. Returns {} if none."""
    contacts = {}
    if not ab_dir:
        return contacts
    for ab in Path(ab_dir).glob('*/AddressBook-v22.abcddb'):
        try:
            c = sqlite3.connect(f'file:{ab}?mode=ro&immutable=1', uri=True)
            names = {}
            for pk, f, l, n, org in c.execute(
                    'SELECT Z_PK,ZFIRSTNAME,ZLASTNAME,ZNICKNAME,ZORGANIZATION '
                    'FROM ZABCDRECORD'):
                f, l = (f or '').strip(), (l or '').strip()
                nm = f'{f} {l}'.strip() or (n or '').strip() or (org or '').strip()
                if nm:
                    names[pk] = nm
            for owner, num in c.execute(
                    'SELECT ZOWNER, ZFULLNUMBER FROM ZABCDPHONENUMBER'):
                if owner in names and num:
                    k = norm(num)
                    if k:
                        contacts.setdefault(k, names[owner])
            for owner, addr in c.execute(
                    'SELECT ZOWNER, ZADDRESS FROM ZABCDEMAILADDRESS'):
                if owner in names and addr:
                    contacts.setdefault(addr.strip().lower(), names[owner])
            c.close()
        except sqlite3.DatabaseError:
            pass
    return contacts


def load_contacts_full(ab_dir):
    """Per-contact records for the browsable contacts.html:
    [{'name', 'org', 'phones': [...], 'emails': [...]}]. Empty if no AddressBook."""
    out = []
    if not ab_dir:
        return out
    for ab in Path(ab_dir).glob('*/AddressBook-v22.abcddb'):
        try:
            c = sqlite3.connect(f'file:{ab}?mode=ro&immutable=1', uri=True)
            recs = {}
            for pk, f, l, n, org in c.execute(
                    'SELECT Z_PK,ZFIRSTNAME,ZLASTNAME,ZNICKNAME,ZORGANIZATION '
                    'FROM ZABCDRECORD'):
                f, l = (f or '').strip(), (l or '').strip()
                name = f'{f} {l}'.strip() or (n or '').strip() or (org or '').strip()
                if name:
                    recs[pk] = {'name': name, 'org': (org or '').strip(),
                                'phones': [], 'emails': []}
            for owner, num in c.execute('SELECT ZOWNER, ZFULLNUMBER FROM ZABCDPHONENUMBER'):
                if owner in recs and num:
                    recs[owner]['phones'].append(num.strip())
            for owner, addr in c.execute('SELECT ZOWNER, ZADDRESS FROM ZABCDEMAILADDRESS'):
                if owner in recs and addr:
                    recs[owner]['emails'].append(addr.strip())
            c.close()
            out.extend(recs.values())
        except sqlite3.DatabaseError:
            pass
    out.sort(key=lambda r: r['name'].lower())
    return out


def resolve(handle, contacts):
    """Map a chat.db handle (phone/email) to a contact name, else return it as-is."""
    if not handle:
        return '?'
    if handle.lower() in contacts:
        return contacts[handle.lower()]
    k = norm(handle)
    if k and k in contacts:
        return contacts[k]
    return handle


# ─── Naming ──────────────────────────────────────────────────────────────────

def conv_label(chat_name, chat_id, members, contacts):
    """Human label for a conversation.
    1:1  -> the contact name (or the raw handle).
    group-> its display name, else 'Group: a, b, c[, +N]'."""
    if chat_name:
        return chat_name
    others = [m for m in members if m]
    if len(others) <= 1:
        return resolve(chat_id or (others[0] if others else ''), contacts)
    named = [resolve(m, contacts) for m in others]
    head = ', '.join(named[:3])
    return f'Group: {head}' + (f', +{len(named) - 3}' if len(named) > 3 else '')


def conv_folder(label, identity_key):
    """Stable, readable, collision-free folder name: '<label>__<hash8>'.
    The suffix is a hash of the conversation IDENTITY (not the chat GUID), so it
    is unique per conversation yet stable across runs."""
    base = san(label).strip() or 'chat'
    base = base[:60].rstrip(' ._')
    suffix = hashlib.sha1(str(identity_key).encode('utf-8')).hexdigest()[:8]
    return f'{base}__{suffix}'


def media_name(ts_iso, orig, seq):
    """Date-prefixed, filesystem-safe media filename for the browsable view."""
    stamp = (ts_iso or '').replace(':', '').replace('-', '').replace('T', '_')[:15]
    stem = san(orig or f'attachment_{seq}')
    return f'{stamp or "00000000_000000"}_{stem}'


# ─── State / dedup ───────────────────────────────────────────────────────────

def load_state(archive):
    try:
        return json.loads((Path(archive) / 'state.json').read_text(encoding='utf-8'))
    except (OSError, json.JSONDecodeError):
        return {'last_date': 0}


def save_state(archive, last_date, total):
    (Path(archive) / 'state.json').write_text(
        json.dumps({'last_date': int(last_date), 'messages': int(total)}, indent=2),
        encoding='utf-8')


def load_seen_guids(manifest_path):
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


def rel_attachment_path(filename, attach_subdir):
    if not filename:
        return None
    i = filename.find(ATTACH_MARKER)
    if i == -1:
        return f'{attach_subdir}/{Path(filename).name}'
    return attach_subdir + '/' + filename[i + len(ATTACH_MARKER):]


# ─── Step 1: ingest new messages into the append-only manifest ───────────────

def ingest(db, archive, attach_subdir, full):
    archive = Path(archive)
    archive.mkdir(parents=True, exist_ok=True)
    manifest_path = archive / 'manifest.jsonl'

    state = {'last_date': 0} if full else load_state(archive)
    watermark = int(state.get('last_date', 0) or 0)
    seen = load_seen_guids(manifest_path)

    conn = sqlite3.connect(f'file:{db}?mode=ro&immutable=1', uri=True)
    conn.row_factory = sqlite3.Row
    rows = conn.execute(
        'SELECT m.ROWID AS rowid, m.guid AS guid, m.date AS date, '
        '       m.is_from_me AS is_from_me, m.text AS text, '
        '       m.attributedBody AS ab, h.id AS handle_id, '
        '       c.guid AS chat_guid, c.chat_identifier AS chat_identifier, '
        '       c.display_name AS display_name '
        'FROM message m '
        'JOIN chat_message_join cmj ON cmj.message_id=m.ROWID '
        'JOIN chat c ON c.ROWID=cmj.chat_id '
        'LEFT JOIN handle h ON h.ROWID=m.handle_id '
        'WHERE m.date > ? GROUP BY m.ROWID ORDER BY m.date', (watermark,)).fetchall()

    new_entries = []
    max_date = watermark
    for m in rows:
        guid = m['guid']
        if not guid or guid in seen:
            continue
        seen.add(guid)
        date_raw = int(m['date'] or 0)
        max_date = max(max_date, date_raw)
        try:
            ts = mts(date_raw).astimezone().isoformat()
        except (ValueError, OverflowError, OSError):
            ts = ''
        atts = []
        for a in conn.execute(
                'SELECT a.filename, a.mime_type, a.transfer_name FROM attachment a '
                'JOIN message_attachment_join maj ON maj.attachment_id=a.ROWID '
                'WHERE maj.message_id=?', (m['rowid'],)).fetchall():
            ext = Path(a['transfer_name'] or a['filename'] or '').suffix.lower()
            atts.append({
                'orig': a['transfer_name'] or (Path(a['filename']).name if a['filename'] else None),
                'mime': a['mime_type'], 'kind': knd(a['mime_type'], ext),
                'path': rel_attachment_path(a['filename'], attach_subdir),
            })
        new_entries.append({
            'guid': guid, 'ts': ts, 'date_raw': date_raw,
            'chat_guid': m['chat_guid'], 'chat_id': m['chat_identifier'],
            'chat_name': (m['display_name'] or '').strip(),
            'sender_handle': None if m['is_from_me'] else m['handle_id'],
            'from_me': int(m['is_from_me'] or 0),
            'text': get_body(m['text'], m['ab']), 'attachments': atts,
        })
    conn.close()

    if new_entries:
        with manifest_path.open('a', encoding='utf-8') as fh:
            for e in new_entries:
                fh.write(json.dumps(e, ensure_ascii=False) + '\n')
    save_state(archive, max_date, len(seen))
    return len(new_entries), len(seen)


# ─── Step 2: regenerate the human-facing views from the full manifest ────────

def read_manifest(manifest_path):
    out = []
    with Path(manifest_path).open(encoding='utf-8') as fh:
        for line in fh:
            line = line.strip()
            if line:
                try:
                    out.append(json.loads(line))
                except json.JSONDecodeError:
                    pass
    return out


HTML_HEAD = """<!DOCTYPE html><html><head><meta charset="utf-8">
<title>{title}</title><style>
body{{font:15px -apple-system,Helvetica,Arial,sans-serif;background:#f2f2f7;margin:0;padding:24px;color:#000}}
h1{{font-size:20px}} .meta{{color:#666;font-size:13px;margin-bottom:18px}}
.row{{display:flex;margin:6px 0}} .me{{justify-content:flex-end}}
.b{{max-width:70%;padding:8px 12px;border-radius:18px;white-space:pre-wrap;word-wrap:break-word}}
.them .b{{background:#e5e5ea;color:#000;border-bottom-left-radius:4px}}
.me .b{{background:#1982fc;color:#fff;border-bottom-right-radius:4px}}
.who{{font-size:11px;color:#888;margin:8px 4px 0}} .ts{{font-size:10px;color:#aaa;margin:2px 4px}}
img,video{{max-width:280px;max-height:280px;border-radius:12px;display:block;margin:3px 0}}
a.file{{color:inherit}}
</style></head><body><h1>{title}</h1><div class="meta">{meta}</div>
"""


def render_html(label, entries, folder_dir):
    rows = []
    last_who = None
    for e in entries:
        me = e.get('from_me')
        who = 'Me' if me else (e.get('_sender_name') or e.get('sender_handle') or '?')
        side = 'me' if me else 'them'
        if who != last_who and not me:
            rows.append(f'<div class="who">{html.escape(str(who))}</div>')
        last_who = who
        body = html.escape(e.get('text') or '')
        media_html = ''
        for at in e.get('attachments', []):
            mp = at.get('_media_rel')
            if not mp:
                continue
            k = at.get('kind')
            if k == 'photo':
                media_html += f'<img src="{html.escape(mp)}" loading="lazy">'
            elif k == 'video':
                media_html += f'<video src="{html.escape(mp)}" controls preload="none"></video>'
            else:
                media_html += f'<a class="file" href="{html.escape(mp)}">📎 {html.escape(at.get("orig") or "file")}</a><br>'
        inner = body
        if media_html:
            inner = (body + '<br>' if body else '') + media_html
        if not inner:
            inner = '<i>(no content)</i>'
        ts = (e.get('ts') or '')[:19].replace('T', ' ')
        rows.append(f'<div class="row {side}"><div class="b">{inner}</div></div>'
                    f'<div class="ts {side}" style="text-align:{"right" if me else "left"}">{ts}</div>')
    meta = f'{len(entries)} messages'
    if entries:
        meta += f' · {entries[0]["ts"][:10]} → {entries[-1]["ts"][:10]}'
    doc = HTML_HEAD.format(title=html.escape(label), meta=html.escape(meta)) + '\n'.join(rows) + '</body></html>'
    (folder_dir / 'index.html').write_text(doc, encoding='utf-8')


CONTACTS_HTML_HEAD = """<!DOCTYPE html><html><head><meta charset="utf-8">
<title>Contacts ({n})</title><style>
body{{font:15px -apple-system,Helvetica,Arial,sans-serif;background:#f2f2f7;margin:0;padding:24px;color:#000}}
h1{{font-size:20px}} input{{font-size:15px;padding:8px 12px;width:280px;border:1px solid #ccc;border-radius:8px;margin-bottom:16px}}
.c{{background:#fff;border-radius:12px;padding:12px 16px;margin:8px 0;max-width:640px}}
.n{{font-weight:600;font-size:16px}} .org{{color:#666;font-size:13px}}
.h{{color:#333;font-size:13px;margin-top:4px}} a{{color:#1982fc;text-decoration:none}}
</style></head><body><h1>Contacts ({n})</h1>
<input id="q" placeholder="Filter contacts…" oninput="f()">
<div id="list">
"""

CONTACTS_HTML_TAIL = """</div><script>
function f(){var q=document.getElementById('q').value.toLowerCase();
document.querySelectorAll('.c').forEach(function(e){
e.style.display=e.textContent.toLowerCase().indexOf(q)<0?'none':''});}
</script></body></html>"""


def render_contacts_html(archive, full_contacts, handle_to_folder):
    cards = []
    for r in full_contacts:
        link = None
        for p in r['phones']:
            link = handle_to_folder.get(norm(p))
            if link:
                break
        if not link:
            for em in r['emails']:
                link = handle_to_folder.get(em.lower())
                if link:
                    break
        bits = [f'<div class="n">{html.escape(r["name"])}</div>']
        if r['org'] and r['org'] != r['name']:
            bits.append(f'<div class="org">{html.escape(r["org"])}</div>')
        for p in r['phones']:
            bits.append(f'<div class="h">📞 {html.escape(p)}</div>')
        for em in r['emails']:
            bits.append(f'<div class="h">✉️ {html.escape(em)}</div>')
        if link:
            bits.append(f'<div class="h"><a href="conversations/{html.escape(link)}/index.html">→ conversation</a></div>')
        cards.append('<div class="c">' + ''.join(bits) + '</div>')
    doc = (CONTACTS_HTML_HEAD.format(n=len(full_contacts)) + '\n'.join(cards)
           + CONTACTS_HTML_TAIL)
    (Path(archive) / 'contacts.html').write_text(doc, encoding='utf-8')


def build_views(archive, attach_subdir, contacts, addressbook_dir=None):
    archive = Path(archive)
    entries = read_manifest(archive / 'manifest.jsonl')
    conv_root = archive / 'conversations'
    conv_root.mkdir(parents=True, exist_ok=True)

    # Determine each chat's member set first, so we can tell a 1:1 from a group.
    members_by_cg = defaultdict(set)
    for e in entries:
        cg = e.get('chat_guid') or e.get('chat_id') or 'unknown'
        if e.get('sender_handle'):
            members_by_cg[cg].add(e['sender_handle'])

    def identity_of(e):
        """Group key: a 1:1 chat is keyed by its handle (so iMessage + SMS with
        the same person MERGE into one folder); a group chat is keyed by its GUID
        (kept separate)."""
        cg = e.get('chat_guid') or e.get('chat_id') or 'unknown'
        if len(members_by_cg.get(cg, set())) <= 1:           # 1:1 (or all-from-me)
            cid = e.get('chat_id') or ''
            return '1:' + (norm(cid) or cid.lower() or cg)
        return 'g:' + cg

    groups = defaultdict(list)
    for e in entries:
        groups[identity_of(e)].append(e)

    index_rows = []
    handle_to_folder = {}        # 1:1 identity tail -> conversation folder (for contacts.html)
    media_copied = 0
    for key, msgs in groups.items():
        msgs.sort(key=lambda x: x.get('date_raw', 0))
        members = sorted({m.get('sender_handle') for m in msgs if m.get('sender_handle')})
        chat_name = next((m.get('chat_name') for m in msgs if m.get('chat_name')), '')
        chat_id = next((m.get('chat_id') for m in msgs if m.get('chat_id')), '')
        label = conv_label(chat_name, chat_id, members, contacts)
        folder = conv_folder(label, key)
        if key.startswith('1:'):
            handle_to_folder[key[2:]] = folder
        d = conv_root / folder
        media_d = d / 'media'
        d.mkdir(parents=True, exist_ok=True)

        tx = [f'Conversation: {label}', f'Messages: {len(msgs)}']
        if msgs:
            tx.append(f'Range: {msgs[0]["ts"][:10]} → {msgs[-1]["ts"][:10]}')
        tx.append('=' * 60)
        n_media = 0
        for e in msgs:
            e['_sender_name'] = 'Me' if e.get('from_me') else resolve(e.get('sender_handle'), contacts)
            ts = (e.get('ts') or '')[:19].replace('T', ' ')
            line = f'[{ts}] {e["_sender_name"]}:'
            if e.get('text'):
                line += f' {e["text"]}'
            tx.append(line)
            for i, at in enumerate(e.get('attachments', [])):
                src_rel = at.get('path')
                src = archive / src_rel if src_rel else None
                dest_name = media_name(e.get('ts'), at.get('orig'), i)
                if src and src.exists():
                    media_d.mkdir(parents=True, exist_ok=True)
                    dest = media_d / dest_name
                    if not dest.exists():
                        try:
                            shutil.copy2(src, dest)
                            media_copied += 1
                        except OSError:
                            pass
                    at['_media_rel'] = f'media/{dest_name}'
                    n_media += 1
                    tx.append(f'    [{at.get("kind")}] {at.get("orig") or "?"} -> media/{dest_name}')
                else:
                    tx.append(f'    [{at.get("kind")}] {at.get("orig") or "?"} -> (not in archive yet)')
        (d / 'transcript.txt').write_text('\n'.join(tx) + '\n', encoding='utf-8')
        render_html(label, msgs, d)
        index_rows.append({
            'name': label, 'folder': folder, 'messages': len(msgs),
            'first': msgs[0]['ts'][:10] if msgs else '',
            'last': msgs[-1]['ts'][:10] if msgs else '', 'media': n_media,
        })

    index_rows.sort(key=lambda r: r['last'], reverse=True)
    with (archive / '_index.csv').open('w', newline='', encoding='utf-8') as fh:
        w = csv.DictWriter(fh, fieldnames=['name', 'folder', 'messages', 'first', 'last', 'media'])
        w.writeheader()
        w.writerows(index_rows)

    # Preserve the resolved contact map + render a browsable contacts.html.
    if contacts:
        with (archive / 'contacts.csv').open('w', newline='', encoding='utf-8') as fh:
            w = csv.writer(fh)
            w.writerow(['handle_or_norm', 'name'])
            for k, v in sorted(contacts.items()):
                w.writerow([k, v])
    full = load_contacts_full(addressbook_dir)
    if full:
        render_contacts_html(archive, full, handle_to_folder)

    return len(groups), media_copied


def run_archive(db, archive, attach_subdir='attachments', addressbook_dir=None, full=False):
    appended, total = ingest(db, archive, attach_subdir, full)
    contacts = load_contacts(addressbook_dir)
    convos, media_copied = build_views(archive, attach_subdir, contacts, addressbook_dir)
    return {'appended': appended, 'total_messages': total, 'conversations': convos,
            'media_copied': media_copied, 'contacts': len(contacts)}


def main():
    ap = argparse.ArgumentParser(
        prog='archive_messages',
        description='Append-only, human-browsable, all-conversations Messages archiver.')
    ap.add_argument('--db', required=True, help='path to a chat.db (snapshot is fine)')
    ap.add_argument('--archive', required=True, help='archive root directory')
    ap.add_argument('--attachments-subdir', default='attachments',
                    help='subdir under the archive where media is mirrored')
    ap.add_argument('--addressbook-dir', default=None,
                    help='a pulled AddressBook "Sources" dir for contact-name resolution')
    ap.add_argument('--full', action='store_true',
                    help='ignore the watermark and re-scan the whole db (GUID-deduped)')
    ap.add_argument('--version', action='version', version=f'%(prog)s {__version__}')
    a = ap.parse_args()
    if not Path(a.db).exists():
        ap.error(f'chat.db not found: {a.db}')
    r = run_archive(a.db, a.archive, attach_subdir=a.attachments_subdir,
                    addressbook_dir=a.addressbook_dir, full=a.full)
    print(f'Messages archive: +{r["appended"]} new message(s); {r["total_messages"]} total '
          f'across {r["conversations"]} conversation(s); copied {r["media_copied"]} media file(s); '
          f'{r["contacts"]} contacts resolved.')


if __name__ == '__main__':
    main()
