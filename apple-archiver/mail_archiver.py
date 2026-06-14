#!/usr/bin/env python3
# =============================================================================
#   APPLE MAIL ARCHIVER
#   File:     mail_archiver.py
#   Version:  1.0.0
#   Requires: Python 3.9+ (standard library only)
#
#   Permanent, append-only, browsable archive of Apple Mail from a pulled copy of
#   ~/Library/Mail/V<n>/ (V9 = macOS 12). Each message is an .emlx file: a leading
#   byte-count line, the raw RFC-2822 message, then a trailing flags plist. Messages
#   with attachments are .partial.emlx, whose attachment files live in a sibling
#   Data/Attachments/<msgnum>/<part>/ tree.
#
#   Emails are immutable, so the manifest is keyed by a stable per-stored-message id
#   (account + mailbox + message number) and only grows — deletions on the source are
#   preserved. Views (re-importable .eml + readable HTML + a sortable index) are
#   regenerated each run; attachments are extracted to a browsable attachments/ tree.
#
#   Usage:  mail_archiver.py --mail-store <…/Mail/V9> --archive <dir>
# =============================================================================
import argparse
import email
import email.policy
import email.utils
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from applearchive_common import (  # noqa: E402
    s, san, slug, short_hash, content_hash,
    load_manifest, manifest_keys, append_manifest, latest_per_id, write_csv,
    html_page, esc,
)

__version__ = '1.0.0'


# ─── .emlx parsing ───────────────────────────────────────────────────────────
def emlx_rfc822_bytes(path):
    """The raw RFC-2822 message bytes inside an .emlx (drops the leading byte-count
    line and the trailing flags plist). This is a valid, re-importable .eml."""
    try:
        data = path.read_bytes()
    except OSError:
        return None
    nl = data.find(b'\n')
    if nl < 0:
        return None
    head = data[:nl].strip()
    try:
        count = int(head)
        return data[nl + 1:nl + 1 + count]
    except ValueError:
        idx = data.rfind(b'<?xml')      # no byte-count → strip trailing plist if any
        return data[:idx] if idx > 0 else data


def parse_emlx(path):
    """Return an email.message.EmailMessage from an .emlx/.partial.emlx, or None."""
    raw = emlx_rfc822_bytes(path)
    if raw is None:
        return None
    try:
        return email.message_from_bytes(raw, policy=email.policy.default)
    except Exception:
        return None


def _hdr(msg, name):
    """Decoded header as a clean one-line string, or ''."""
    try:
        v = msg[name]
    except Exception:
        v = None
    if v is None:
        return ''
    return ' '.join(str(v).split())


def _date(msg):
    """(iso_string, sortable_string) from the Date header; ('', '') on failure."""
    raw = msg['Date'] if 'Date' in msg else None
    if not raw:
        return '', ''
    try:
        dt = email.utils.parsedate_to_datetime(str(raw))
        if dt is None:
            return s(raw), ''
        return dt.strftime('%Y-%m-%d %H:%M'), dt.strftime('%Y-%m-%d %H:%M')
    except (TypeError, ValueError, OverflowError):
        return ' '.join(str(raw).split()), ''


def _body(msg):
    """(text, html) best-effort plain + html bodies."""
    text, htm = '', ''
    try:
        bp = msg.get_body(preferencelist=('plain',))
        if bp is not None:
            text = bp.get_content()
    except Exception:
        pass
    try:
        bh = msg.get_body(preferencelist=('html',))
        if bh is not None:
            htm = bh.get_content()
    except Exception:
        pass
    if not text and not msg.is_multipart() and msg.get_content_type() == 'text/plain':
        try:
            text = msg.get_content()
        except Exception:
            pass
    return text, htm


def _msgnum(path):
    return path.name.split('.', 1)[0]


def _account_labels(mail_store):
    """Map account UUID → friendly label from MailData/Accounts.plist, best-effort."""
    labels = {}
    plist = mail_store / 'MailData' / 'Accounts.plist'
    if not plist.exists():
        return labels
    try:
        import plistlib
        data = plistlib.loads(plist.read_bytes())
    except Exception:
        return labels
    accts = data.get('MailAccounts', data) if isinstance(data, dict) else data
    if isinstance(accts, dict):
        accts = accts.get('Accounts', [])
    for a in (accts or []):
        if not isinstance(a, dict):
            continue
        uuid = a.get('AccountPath') or a.get('UniqueId') or a.get('Identifier') or ''
        emails = a.get('EmailAddresses') or []
        name = (emails[0] if emails else None) or a.get('AccountName') or a.get('Username')
        if uuid and name:
            labels[str(uuid)] = str(name)
    return labels


def _account_of(path, mail_store):
    """Account UUID = first path component under the V<n> store root."""
    try:
        rel = path.relative_to(mail_store)
        return rel.parts[0] if rel.parts else 'Account'
    except ValueError:
        return 'Account'


def _mailbox_of(path):
    """Nearest enclosing *.mbox name → human mailbox name."""
    for p in path.parents:
        if p.name.endswith('.mbox'):
            return p.name[:-5]
    return 'Mailbox'


def _partial_attachments(path):
    """External attachment files for a .partial.emlx: Data/Attachments/<num>/**."""
    out = []
    att_root = path.parent.parent / 'Attachments' / _msgnum(path)
    if att_root.exists():
        for f in sorted(att_root.rglob('*')):
            if f.is_file() and f.name != '.DS_Store':
                out.append(f)
    return out


# ─── reading ─────────────────────────────────────────────────────────────────
def read_mail(mail_store):
    mail_store = Path(mail_store)
    acct_labels = _account_labels(mail_store)
    out, failed = [], 0
    for path in sorted(mail_store.rglob('*.emlx')):
        msg = parse_emlx(path)
        if msg is None:
            failed += 1
            continue
        acct_uuid = _account_of(path, mail_store)
        text, htm = _body(msg)
        is_partial = path.name.endswith('.partial.emlx')
        # Inline attachments (full .emlx) vs external files (.partial.emlx).
        inline, external = [], []
        if is_partial:
            external = _partial_attachments(path)
        else:
            try:
                for part in msg.iter_attachments():
                    fn = part.get_filename()
                    if fn:
                        inline.append(part)
            except Exception:
                pass
        out.append({
            'id': short_hash(acct_uuid, _mailbox_of(path), _msgnum(path)),
            '_src': str(path),        # source .emlx, for the re-importable .eml export
            'account': acct_labels.get(acct_uuid, f'Account {acct_uuid[:8]}'),
            'mailbox': _mailbox_of(path),
            'msgnum': _msgnum(path),
            'from': _hdr(msg, 'From'),
            'to': _hdr(msg, 'To'),
            'cc': _hdr(msg, 'Cc'),
            'subject': _hdr(msg, 'Subject') or '(no subject)',
            'message_id': _hdr(msg, 'Message-ID'),
            'date': _date(msg)[0],
            'sort': _date(msg)[1],
            'text': text or '',
            'html': htm or '',
            '_inline': inline,        # email.message parts (not serialized to manifest)
            '_external': external,    # Path objects (not serialized to manifest)
            'n_att': len(inline) + len(external),
        })
    return out, failed


# ─── views ───────────────────────────────────────────────────────────────────
def _write_attachments(archive, e):
    """Extract this message's attachments to attachments/<id>/, return [(name, rel)].
    Names are de-duplicated (foo.pdf, foo-2.pdf, …) so same-named parts never clobber."""
    saved = []
    dest = archive / 'attachments' / e['id']
    used = set()

    def unique(name):
        name = san(name or 'attachment')
        if name not in used:
            used.add(name); return name
        stem, dot, ext = name.rpartition('.')
        base = stem if dot else name
        suffix = ('.' + ext) if dot else ''
        i = 2
        while f'{base}-{i}{suffix}' in used:
            i += 1
        name = f'{base}-{i}{suffix}'; used.add(name); return name

    for part in e.get('_inline', []):
        try:
            payload = part.get_content()
            if isinstance(payload, str):
                payload = payload.encode('utf-8', 'replace')
        except Exception:
            continue
        fn = unique(part.get_filename())
        dest.mkdir(parents=True, exist_ok=True)
        (dest / fn).write_bytes(payload)
        saved.append((fn, f"attachments/{e['id']}/{fn}"))
    for f in e.get('_external', []):
        try:
            data = f.read_bytes()
        except OSError:
            continue
        fn = unique(f.name)
        dest.mkdir(parents=True, exist_ok=True)
        (dest / fn).write_bytes(data)
        saved.append((fn, f"attachments/{e['id']}/{fn}"))
    return saved


_IMG_EXT = ('.jpg', '.jpeg', '.png', '.gif', '.heic', '.webp', '.tiff', '.bmp')


def _message_html(e, atts):
    rows = ''.join(
        f'<tr><td class="k">{esc(k)}</td><td>{esc(v)}</td></tr>'
        for k, v in [('From', e['from']), ('To', e['to']), ('Cc', e['cc']),
                     ('Date', e['date']), ('Subject', e['subject']),
                     ('Mailbox', f"{e['account']} · {e['mailbox']}")] if v)
    if e['html']:
        body = f'<div class="htmlbody">{e["html"]}</div>'
    else:
        body = f'<pre class="textbody">{esc(e["text"]) or "<em>(no text body)</em>"}</pre>'
    att_html = ''
    if atts:
        items = []
        for name, rel in atts:
            if name.lower().endswith(_IMG_EXT):
                items.append(f'<div><a href="../{esc(rel)}"><img src="../{esc(rel)}" '
                             f'loading="lazy" style="max-width:320px;border-radius:8px"></a>'
                             f'<br><small>{esc(name)}</small></div>')
            else:
                items.append(f'<div><a href="../{esc(rel)}">📎 {esc(name)}</a></div>')
        att_html = ('<h3>Attachments</h3><div class="atts">' + ''.join(items) + '</div>')
    style = ('<style>.hdr{border-collapse:collapse;margin-bottom:8px}'
             '.hdr td{padding:2px 8px;vertical-align:top}.hdr .k{color:#888;text-align:right;'
             'white-space:nowrap}.textbody{white-space:pre-wrap;word-wrap:break-word}'
             '.htmlbody{max-width:900px}.atts>div{display:inline-block;margin:6px;'
             'vertical-align:top}</style>')
    inner = (f'{style}<table class="hdr">{rows}</table><hr>{body}{att_html}'
             '<p><a href="../mail.html">← all mail</a></p>')
    return html_page(e['subject'], inner)


def build_views(archive, entries):
    archive = Path(archive)
    msgs_root = archive / 'messages'
    msgs_root.mkdir(parents=True, exist_ok=True)

    versions = {}
    for e in entries:
        versions[e['id']] = versions.get(e['id'], 0) + 1
    current = latest_per_id(entries)
    current.sort(key=lambda e: e.get('sort') or '', reverse=True)

    cards, index_rows, n_att = [], [], 0
    for e in current:
        atts = _write_attachments(archive, e)
        n_att += len(atts)
        acct_dir = msgs_root / san(e['account']) / san(e['mailbox'])
        acct_dir.mkdir(parents=True, exist_ok=True)
        stem = f"{slug(e['subject'])[:60]}__{short_hash(e['id'])}"

        # Re-importable .eml (the raw RFC-2822 message, lifted from the source .emlx).
        src = e.get('_src')
        if src:
            raw = emlx_rfc822_bytes(Path(src))
            if raw:
                (acct_dir / f'{stem}.eml').write_bytes(raw)
        # Readable HTML render.
        (acct_dir / f'{stem}.html').write_text(_message_html(e, atts), encoding='utf-8')
        html_rel = f"messages/{san(e['account'])}/{san(e['mailbox'])}/{stem}.html"

        index_rows.append({'date': e['date'], 'from': e['from'], 'subject': e['subject'],
                           'account': e['account'], 'mailbox': e['mailbox'],
                           'attachments': len(atts), 'file': html_rel})
        snippet = (e['text'] or '')[:200]
        cards.append(
            f'<div class="item"><div class="t"><a href="{esc(html_rel)}">{esc(e["subject"])}</a></div>'
            f'<div class="meta">{esc(e["from"])} · {esc(e["date"])} · '
            f'{esc(e["account"])}/{esc(e["mailbox"])}'
            f'{" · " + str(len(atts)) + " attachment(s)" if atts else ""}</div>'
            f'<div class="body">{esc(snippet)}</div></div>')

    (archive / 'mail.html').write_text(
        html_page(f'Mail ({len(current)})', '\n'.join(cards)), encoding='utf-8')
    write_csv(archive / '_index.csv',
              ['date', 'from', 'subject', 'account', 'mailbox', 'attachments', 'file'],
              index_rows)
    return len(current), n_att


# ─── run ─────────────────────────────────────────────────────────────────────
def run_archive(mail_store, archive):
    archive = Path(archive)
    archive.mkdir(parents=True, exist_ok=True)
    mpath = archive / 'manifest.jsonl'
    seen = manifest_keys(load_manifest(mpath))

    entries, failed = read_mail(mail_store)
    new = []
    for e in entries:
        key = (e['id'], content_hash(e['subject'], e['from'], e['date'], e['message_id']))
        if key in seen:
            continue
        seen.add(key)
        rec = {k: v for k, v in e.items() if not k.startswith('_')}
        rec['hash'] = key[1]
        new.append(rec)
    append_manifest(mpath, new)

    # Build views off the full manifest, but attachment extraction + .eml export need
    # the live parts/source path, so graft those back from this run's freshly-read
    # entries (older messages no longer on the source keep their text-only manifest row).
    by_id = {e['id']: e for e in entries}
    manifest_entries = load_manifest(mpath)
    for me in manifest_entries:
        live = by_id.get(me.get('id'))
        if live:
            me['_inline'] = live.get('_inline', [])
            me['_external'] = live.get('_external', [])
            me['_src'] = live.get('_src')
    msgs, atts = build_views(archive, manifest_entries)
    return {'new': len(new), 'messages': msgs, 'attachments': atts, 'failed': failed}


def main():
    ap = argparse.ArgumentParser(prog='mail_archiver',
        description='Append-only, browsable Apple Mail archiver (.emlx).')
    ap.add_argument('--mail-store', required=True, help='path to a pulled Mail/V<n> dir')
    ap.add_argument('--archive', required=True, help='archive root directory')
    ap.add_argument('--version', action='version', version=f'%(prog)s {__version__}')
    a = ap.parse_args()
    if not Path(a.mail_store).exists():
        ap.error(f'mail store not found: {a.mail_store}')
    r = run_archive(a.mail_store, a.archive)
    print(f'Mail archive: +{r["new"]} new message(s); {r["messages"]} total; '
          f'{r["attachments"]} attachment(s); {r["failed"]} unparseable.')


if __name__ == '__main__':
    main()
