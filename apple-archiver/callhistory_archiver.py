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
import json
import os
import sys
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from applearchive_common import (  # noqa: E402
    open_ro, rows, has_table, s, cd_date, cd_dt, short_hash, CORE_DATA_EPOCH,
    content_hash, latest_per_id,
    load_manifest, manifest_keys, append_manifest, write_csv, html_page, esc,
)

__version__ = '1.2.0'

CALL_TYPE = {1: 'Phone', 8: 'FaceTime', 16: 'FaceTime Video'}


def _service(provider, ctype):
    """Human service from ZSERVICE_PROVIDER (preferred) else the numeric type."""
    p = s(provider).lower()
    if 'facetime' in p:
        return 'FaceTime'
    if 'telephony' in p or 'phone' in p:
        return 'Phone'
    return CALL_TYPE.get(int(ctype or 0), 'Call')


# ─── Address decryption (investigated; offline-impossible by design) ─────────
def decrypt_address(blob):
    """ZADDRESS / ZNAME are ENCRYPTED AT REST (44-byte AES-GCM blob: ciphertext +
    16-byte IV + 16-byte tag). The key lives in the source Mac's *login* keychain,
    released only to an interactive (Aqua) session. A pulled DB therefore CANNOT be
    decrypted offline — see DECRYPTION.md for the full investigation.

    Evidence (run on the source Mac over SSH, CallHistory.framework via PyObjC):
    `CHManager.recentCalls()` returns every call object, but `remoteParticipantHandles`
    (where the decrypted number would appear) is EMPTY for all of them, with one
    diagnostic: "Failed to get Call History User Data Key from keychain — User
    interaction is not allowed." i.e. the SSH session can't unlock the key; an
    unlocked GUI session is the only context where the number resolves.

    The only viable route is an *in-GUI-session* helper (PyObjC over recentCalls() →
    remoteParticipantHandles[].value), which breaks the pull model and is therefore
    opt-in, not wired in here. This hook returns None so callers fall back to
    '(encrypted)'. Note: for people the user actually texts, the real number is
    already preserved in the Messages + Contacts archives, so the practical loss is
    small — only call-only (never-texted) numbers stay opaque.
    """
    return None


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


def load_decrypted(path):
    """Load a calls_decrypted.json sidecar (produced on the source Mac by
    calls_decrypt_helper.py, the only context where addresses decrypt) into a
    {rounded-unix-epoch: address} map. Timezone-proof: matched on the raw instant,
    not a formatted local time."""
    idx = {}
    if not path or not Path(path).exists():
        return idx
    try:
        data = json.loads(Path(path).read_text(encoding='utf-8'))
    except (OSError, ValueError):
        return idx
    for c in data.get('calls', []):
        ep, addr = c.get('epoch'), (c.get('address') or '').strip()
        if ep is None or not addr:
            continue
        idx[round(float(ep))] = addr
    return idx


def read_calls(db, decrypted=None):
    decrypted = decrypted or {}
    conn = open_ro(db)
    if not has_table(conn, 'ZCALLRECORD'):
        conn.close(); return []
    cols = {r[1] for r in rows(conn, 'PRAGMA table_info(ZCALLRECORD)')}
    cc = 'ZISO_COUNTRY_CODE' if 'ZISO_COUNTRY_CODE' in cols else 'NULL'
    sp = 'ZSERVICE_PROVIDER' if 'ZSERVICE_PROVIDER' in cols else 'NULL'
    out = []
    for addr, name, orig, ctype, answered, dur, date, svc, country in rows(conn,
            f'SELECT ZADDRESS, ZNAME, ZORIGINATED, ZCALLTYPE, ZANSWERED, '
            f'       ZDURATION, ZDATE, {sp}, {cc} FROM ZCALLRECORD'):
        when = cd_date(date, '%Y-%m-%d %H:%M:%S')
        addr_s = _addr(addr)
        if addr_s == '(encrypted)':
            addr_s = decrypt_address(addr) or '(encrypted)'   # offline hook (always None)
            if addr_s == '(encrypted)' and decrypted and date is not None:
                # Fold in a number recovered by the GUI-session helper, matched on
                # the raw call instant (±1s for rounding).
                ep = round(float(date) + CORE_DATA_EPOCH)
                for k in (ep, ep - 1, ep + 1):
                    if k in decrypted:
                        addr_s = decrypted[k]; break
        name_s = _addr(name)
        out.append({
            # Address-independent identity (the call instant + shape) so a later
            # GUI-helper decryption *upgrades* the same call instead of duplicating it.
            'id': short_hash(when, s(dur), 'out' if orig else 'in'),
            'address': addr_s, 'name': name_s if name_s != '(encrypted)' else '',
            'direction': 'outgoing' if orig else 'incoming',
            'kind': _service(svc, ctype),
            'answered': bool(answered),
            'missed': bool(not answered and not orig),
            'duration': _dur(dur), 'date': when,
            'service': s(svc), 'country': s(country).upper(),
        })
    conn.close()
    return out


def build_views(archive, entries):
    archive = Path(archive)
    entries = latest_per_id(entries)     # newest version of each call (decrypted > encrypted)
    entries = sorted(entries, key=lambda e: e.get('date') or '', reverse=True)

    # Per-call HTML + CSV.
    cards, csv_rows = [], []
    by_addr = {}
    for e in entries:
        who = e['name'] or e['address'] or 'Unknown'
        arrow = '↗' if e['direction'] == 'outgoing' else ('↙' if e['answered'] else '✖')
        miss = ' missed' if e['missed'] else ''
        meta = ' · '.join(x for x in [e['kind'], e['duration'], e.get('country')] if x)
        cards.append(f'<div class="item{miss}"><div class="t">{arrow} {esc(who)}'
                     f'{" (missed)" if e["missed"] else ""}</div>'
                     f'<div class="meta">{esc(e["date"])} · {esc(meta)}'
                     f'{" · " + esc(e["address"]) if e["name"] else ""}</div></div>')
        csv_rows.append({'date': e['date'], 'who': who, 'address': e['address'],
                         'direction': e['direction'], 'kind': e['kind'],
                         'country': e.get('country', ''),
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
              ['date', 'who', 'address', 'direction', 'kind', 'country', 'answered', 'duration'],
              csv_rows)
    idx = [{'who': v['name'] or k, 'address': k, 'calls': v['calls'], 'missed': v['missed']}
           for k, v in sorted(by_addr.items(), key=lambda kv: kv[1]['calls'], reverse=True)]
    write_csv(archive / '_index.csv', ['who', 'address', 'calls', 'missed'], idx)
    return len(entries)


def run_archive(db, archive, decrypted_path=None):
    archive = Path(archive); archive.mkdir(parents=True, exist_ok=True)
    mpath = archive / 'manifest.jsonl'
    seen = manifest_keys(load_manifest(mpath))
    decrypted = load_decrypted(decrypted_path)
    new = []
    for e in read_calls(db, decrypted):
        # Versioned by (id, content-hash of the address/name): a call first seen
        # '(encrypted)' and later recovered with a real number appends a new
        # version; build_views shows the latest. Nothing is ever rewritten.
        key = (e['id'], content_hash(e['address'], e['name']))
        if key in seen:
            continue
        seen.add(key)
        rec = dict(e); rec['hash'] = key[1]
        new.append(rec)
    append_manifest(mpath, new)
    total = build_views(archive, load_manifest(mpath))
    return {'new': len(new), 'calls': total}


def main():
    ap = argparse.ArgumentParser(prog='callhistory_archiver',
        description='Append-only Apple call-history archiver.')
    ap.add_argument('--db', required=True, help='path to CallHistory.storedata')
    ap.add_argument('--archive', required=True, help='archive root directory')
    ap.add_argument('--decrypted', default=None,
                    help='optional calls_decrypted.json from calls_decrypt_helper.py '
                         '(run on the source Mac in a GUI session) to fill in numbers')
    ap.add_argument('--version', action='version', version=f'%(prog)s {__version__}')
    a = ap.parse_args()
    if not Path(a.db).exists():
        ap.error(f'CallHistory.storedata not found: {a.db}')
    r = run_archive(a.db, a.archive, decrypted_path=a.decrypted)
    print(f'Call history: +{r["new"]} new call(s); {r["calls"]} total.')


if __name__ == '__main__':
    main()
